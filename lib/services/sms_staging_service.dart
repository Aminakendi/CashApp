import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class StagedSms {
  final File file;
  final String content;

  StagedSms(this.file, this.content);
}

class SmsStagingService {
  static const _stagingDirName = 'sms_staging';
  static const _uuid = Uuid();

  static Future<Directory> _getStagingDir() async {
    final docDir = await getApplicationSupportDirectory();
    final stagingDir = Directory('${docDir.path}/$_stagingDirName');
    if (!await stagingDir.exists()) {
      await stagingDir.create(recursive: true);
    }
    return stagingDir;
  }

  /// Called by the background isolate to quickly stash an incoming SMS
  /// without opening the encrypted database.
  static Future<void> queueMessage(String rawSms) async {
    final dir = await _getStagingDir();
    final id = _uuid.v4();
    final tempFile = File('${dir.path}/mpesa_queue_$id.tmp');
    final finalFile = File('${dir.path}/mpesa_queue_$id.txt');
    
    // Write to a temporary file first, then atomically rename to .txt
    await tempFile.writeAsString(rawSms);
    await tempFile.rename(finalFile.path);
  }

  /// Called by the main isolate to retrieve pending messages WITHOUT deleting them.
  /// Limits to reading the oldest 200 files in a single pass to prevent OOM.
  static Future<List<StagedSms>> drainQueue() async {
    final dir = await _getStagingDir();
    if (!await dir.exists()) return [];

    final files = dir.listSync().whereType<File>().toList();
    
    // Sort files by last modified to process oldest first
    files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
    
    final messages = <StagedSms>[];
    
    // Clean up old .tmp files that might have been left over from crashes
    final now = DateTime.now();
    
    for (final file in files) {
      if (file.path.endsWith('.tmp')) {
        if (now.difference(file.lastModifiedSync()).inDays > 7) {
          try { await file.delete(); } catch (_) {}
        }
        continue;
      }
      
      if (file.path.endsWith('.txt')) {
        if (messages.length >= 200) break; // Limit batch size
        
        try {
          final content = await file.readAsString();
          if (content.isNotEmpty) {
            messages.add(StagedSms(file, content));
          }
        } catch (e) {
          // Ignore read errors for individual files, they will be retried next drain
        }
      }
    }
    return messages;
  }
  
  /// Called after successful database ingestion to safely delete the staged files.
  static Future<void> deleteStagedFiles(List<StagedSms> stagedMessages) async {
    for (final staged in stagedMessages) {
      try {
        await staged.file.delete();
      } catch (e) {
        // Ignore errors such as PathNotFoundException if another drain concurrently deleted it
      }
    }
  }
}

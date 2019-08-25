import 'dart:io';

class FileInfo {
  String domain;
  File file;
  String path;
  int size;
  String mimeType;
  String ext;
  Map<String, String> params;
  String hash;
  String key;

  FileInfo({
    this.domain,
    this.file,
    this.key,
    this.path,
    this.size,
    this.mimeType,
    this.ext,
    this.params,
  });

  Map<String, dynamic> toJson() => {
        'domain': domain == null ? null : domain,
        'file': file == null ? null : file,
        'key': key == null ? null : key,
        'path': path == null ? null : path,
        'size': size == null ? null : size,
        'mimeType': mimeType == null ? null : mimeType,
        'ext': ext == null ? null : ext,
        'params': params == null ? null : params,
      };
}

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';

class QiniuUploader {
  final Uuid uuid = Uuid();
  final Dio dio = Dio();

  Future<void> formUpload(String token, String key, String filePath) async {
    final File file = File(filePath);
    if (!file.existsSync())
      throw Exception('[QiniuUploader] putFile() file no exists');
    final int size = file.lengthSync();
    final String mimeType = lookupMimeType(filePath);
    final String ext = extension(filePath);
    final String fileName = uuid.v4() + ext;

    print('| path => $filePath');
    print('| size => $size');
    print('| mime => $mimeType');
    print('| name => $fileName');
    print('| key => $key');
    print('| _ _ _ _ _ _ _ _ _ _ _ _ _');

    const String url = 'http://upload-z2.qiniup.com';
    final FormData formData = FormData();
    formData.add('file', UploadFileInfo(file, fileName));
    // formData.add('key', fileName);
    formData.add('key', key);
    formData.add('token', token);
    final Response response = await dio.post(url, data: formData,
        onSendProgress: (int current, int total) {
      print('$current/$total');
    });
    print('response => $response');
  }

  Future<void> resumeUpload(String token, String key, String filePath) async {
    final File file = File(filePath);
    if (!file.existsSync())
      throw Exception('[QiniuUploader] putFile() file no exists');

    // file.openRead().listen((data) => print(data));
  }
}

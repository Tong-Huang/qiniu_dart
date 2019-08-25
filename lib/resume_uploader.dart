import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';

class QiniuUploader {
  final Uuid uuid = Uuid();
  final Dio dio = Dio();
  final String domain = 'http://upload-z2.qiniup.com';

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
    final response = await dio.post(url, data: formData,
        onSendProgress: (int current, int total) {
      print('[formUpload] $current/$total');
    });
    print('response => $response');
  }

  Future<void> resumeUpload(String token, String key, String filePath) async {
    final File file = File(filePath);
    if (!file.existsSync())
      throw Exception('[QiniuUploader] putFile() file no exists');
    final int fileSize = file.lengthSync();
    final String mimeType = lookupMimeType(filePath);
    final String ext = extension(filePath);
    final String fileName = uuid.v4() + ext;

    print('| path => $filePath');
    print('| size => $fileSize');
    print('| mime => $mimeType');
    print('| name => $fileName');
    print('| key => $key');
    print('| _ _ _ _ _ _ _ _ _ _ _ _ _');

    int readLen = 0;
    int bufferLen = 0;
    int currentBlock = 0;
    int finishedBlock = 0;
    List<int> remainedData = [];
    List<int> readBuffers = [];
    StreamSubscription streamSubscription;
    const int BLOCK_SIZE = 4 * 1024 * 1024; //4MB, never change
    streamSubscription = file.openRead().listen((chunk) async {
      readLen += chunk.length;
      bufferLen += chunk.length;
      readBuffers.addAll(chunk);

      if (bufferLen >= BLOCK_SIZE - 1 || readLen == fileSize) {
        streamSubscription.pause();
        final int blockSize = BLOCK_SIZE - remainedData.length;
        final List<int> buffersData = readBuffers.sublist(0, blockSize);
        final List<int> postData = List<int>.from(remainedData);
        postData.addAll(buffersData);

        // something reset
        remainedData = readBuffers.sublist(blockSize);
        bufferLen = bufferLen - BLOCK_SIZE;
        readBuffers = [];

        currentBlock += 1;

        await _mkblk(domain, token, postData);

        // streamSubscription.resume();
        streamSubscription.cancel();
      }
    }, onDone: () {
      print('finish read file size => $bufferLen');
      streamSubscription.cancel();
    });
  }

  Future<void> _mkblk(String domain, String token, List<int> data) async {
    try {
      final String url = '$domain/mkblk/${data.length}';
      final String auth = 'UpToken $token';
      final headers = {
        'Authorization': auth,
        'Content-Type': 'application/octet-stream',
        'Connection': 'keep-alive'
      };
      // final Response response =
      //     await dio.post(url, data: data, options: Options(headers: headers));
      // return response;

      final response = await http.post(url, body: data, headers: headers);

      print(jsonEncode(response.body));
    } on DioError catch (e) {
      print(e);
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crclib/crclib.dart';
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
    final List<String> finishedCtxList = [];
    final List<String> finishedBlkPutRets = [];

    StreamSubscription streamSubscription;
    const int BLOCK_SIZE = 4 * 1024 * 1024; //4MB, never change
    streamSubscription = file.openRead().listen((chunk) async {
      readLen += chunk.length;
      bufferLen += chunk.length;
      readBuffers.addAll(chunk);

      if (bufferLen >= BLOCK_SIZE || readLen == fileSize) {
        streamSubscription.pause();
        int blockSize = BLOCK_SIZE - remainedData.length;
        blockSize = min(bufferLen, blockSize);
        final List<int> buffersData = readBuffers.sublist(0, blockSize);
        final List<int> postData = List<int>.from(remainedData);
        postData.addAll(buffersData);

        // something reset
        remainedData = readBuffers.sublist(blockSize);
        bufferLen = bufferLen - BLOCK_SIZE;
        readBuffers = [];

        currentBlock += 1;

        final int bodyCrc32 = Crc32Zlib().convert(postData);
        final Response response = await _mkblk(domain, token, postData);

        if (response == null) {
          streamSubscription.cancel();
          throw Exception('No Response');
        }

        final String ctx = response.data['ctx'];
        final int crc32 = response.data['crc32'];

        if (crc32 != bodyCrc32) {
          streamSubscription.cancel();
          throw Exception('CRC32 no match.');
        }

        finishedBlock += 1;
        finishedCtxList.add(ctx);
        finishedBlkPutRets.add(jsonEncode(response.data));
        streamSubscription.resume();
      }
    }, onDone: () async {
      print('finish read file size => $bufferLen');
      // TODO(thuang): check remain buffer and buffer, deal with more than block size case.

      // streamSubscription.cancel();
      await _mkfile(domain, token, fileSize, finishedCtxList, key);
    });
  }

  Future<Response> _mkblk(String domain, String token, List<int> data) async {
    try {
      final String url = '$domain/mkblk/${data.length}';
      final String auth = 'UpToken $token';
      final headers = {
        'Authorization': auth,
        'Content-Type': 'application/octet-stream',
        'Connection': 'keep-alive',
        HttpHeaders.contentLengthHeader: data.length
      };
      final Response response = await dio.post(url,
          data: Stream.fromIterable(data.map((e) => [e])),
          options: Options(headers: headers));
      return response;
    } on DioError catch (e) {
      print(jsonEncode(e));
      return null;
    }
  }

  Future<Response> _mkfile(String domain, String token, int fileSize,
      List<String> ctxList, String key) async {
    try {
      String url = '$domain/mkfile/$fileSize';
      url += '/key/' + _urlsafeBase64Encode(key);
      final String auth = 'UpToken $token';
      final String postBody = ctxList.join(',');
      final headers = {
        'Authorization': auth,
        'Content-Type': 'application/octet-stream',
        'Connection': 'keep-alive',
        HttpHeaders.contentLengthHeader: postBody.length
      };
      final Response response = await dio.post(url,
          data: postBody, options: Options(headers: headers));
      return response;
    } on DioError catch (e) {
      print(jsonEncode(e));
      return null;
    }
  }

  String _urlsafeBase64Encode(String str) {
    final List<int> bytes = utf8.encode(str);
    final String base64Str = base64.encode(bytes);
    return base64Str
        .replaceAll(RegExp(r'\/'), '_')
        .replaceAll(RegExp(r'\+'), '-');
  }
}

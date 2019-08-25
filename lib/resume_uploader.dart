import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crclib/crclib.dart';
import 'package:dio/dio.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';

class FileInfo {
  String domain;
  File file;
  String path;
  int size;
  String mime;
  String ext;
  String name;
  Map<String, String> params;
  String hash;
  String key;

  FileInfo({
    this.domain,
    this.file,
    this.path,
    this.size,
    this.mime,
    this.ext,
    this.name,
    this.params,
  });
}

class QiniuUploader {
  final Uuid uuid = Uuid();
  final Dio dio = Dio();
  static const int BLOCK_SIZE = 4 * 1024 * 1024; //4MB, never change
  final String domain; //z2 client upload domain

  QiniuUploader({this.domain = 'http://upload-z2.qiniup.com'});

  Future<void> formUpload(String token, String fileKey, String filePath) async {
    final FileInfo fileInfo = _generateFileInfo(filePath, fileKey);

    print('| formUpload');
    print('| path => $filePath');
    print('| size => ${fileInfo.size}');
    print('| mime => ${fileInfo.mime}');
    print('| name => ${fileInfo.name}');
    print('| key => $fileKey');
    print('| _ _ _ _ _ _ _ _ _ _ _ _ _');

    final FormData formData = FormData();
    formData.add('file', UploadFileInfo(fileInfo.file, fileInfo.name));
    formData.add('key', fileInfo.name);
    formData.add('token', token);
    // TODO(thuang): handler params.
    final response = await dio.post(domain, data: formData,
        onSendProgress: (int current, int total) {
      print('[formUpload] $current/$total');
    });
    print('response => $response');
  }

  Future<void> resumeUpload(
      String token, String fileKey, String filePath) async {
    final FileInfo fileInfo = _generateFileInfo(filePath, fileKey);
    print('| formUpload');
    print('| path => $filePath');
    print('| size => ${fileInfo.size}');
    print('| mime => ${fileInfo.mime}');
    print('| name => ${fileInfo.name}');
    print('| key => $fileKey');
    print('| _ _ _ _ _ _ _ _ _ _ _ _ _');

    int readLen = 0;
    final List<int> readBuffers = [];
    final List<String> finishedCtxList = [];
    StreamSubscription streamSubscription;

    streamSubscription = fileInfo.file.openRead().listen((chunk) async {
      readLen += chunk.length;
      readBuffers.addAll(chunk);

      if (readBuffers.length >= BLOCK_SIZE || readLen == fileInfo.size) {
        streamSubscription.pause();
        final int blockSize = min(readBuffers.length, BLOCK_SIZE);
        final List<int> postData = readBuffers.sublist(0, blockSize);

        // something reset
        readBuffers.removeRange(0, blockSize);

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
        finishedCtxList.add(ctx);
        streamSubscription.resume();
      }
    }, onDone: () async {
      final Response response = await _mkfile(
          domain, token, fileInfo.size, finishedCtxList, fileInfo.name);
      if (response == null) {
        streamSubscription.cancel();
        throw Exception('No Response');
      }
      print(response.data);
    });
  }

  FileInfo _generateFileInfo(String path, String fileKey) {
    final File file = File(path);
    if (!file.existsSync())
      throw Exception('[QiniuUploader] putFile() file no exists');
    final int size = file.lengthSync();
    final String mime = lookupMimeType(path);
    final String ext = extension(path);
    final String name = fileKey ?? uuid.v4() + ext;
    final FileInfo fileInfo = FileInfo(
        domain: domain,
        file: file,
        size: size,
        path: path,
        mime: mime,
        ext: ext,
        name: name);
    return fileInfo;
  }

  Future<Response> _mkblk(String domain, String token, List<int> data) async {
    try {
      final String url = '$domain/mkblk/${data.length}';
      final String auth = 'UpToken $token';
      final headers = {
        HttpHeaders.authorizationHeader: auth,
        HttpHeaders.contentTypeHeader: 'application/octet-stream',
        HttpHeaders.connectionHeader: 'keep-alive',
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
        HttpHeaders.authorizationHeader: auth,
        HttpHeaders.contentTypeHeader: 'application/octet-stream',
        HttpHeaders.connectionHeader: 'keep-alive',
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

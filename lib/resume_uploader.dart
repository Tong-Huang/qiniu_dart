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
}

class QiniuUploader {
  final Uuid uuid = Uuid();
  final Dio dio = Dio();
  static const int BLOCK_SIZE = 4 * 1024 * 1024; //4MB, never change
  final String domain; //z2 client upload domain
  String token;

  QiniuUploader({this.domain = 'http://upload-z2.qiniup.com', this.token});

  Future<void> formUpload(String fileKey, String filePath,
      {Map<String, String> params}) async {
    final FileInfo fileInfo = _generateFileInfo(filePath, fileKey);
    FormData formData = FormData();
    formData.add('file', UploadFileInfo(fileInfo.file, fileInfo.key));
    formData.add('key', fileInfo.key);
    formData.add('token', token);
    formData = _handleParams(params, formData: formData);
    final response = await dio.post(domain, data: formData,
        onSendProgress: (int current, int total) {
      print('[formUpload] $current/$total');
    });
    print('response => $response');
  }

  Future<void> resumeUpload(String fileKey, String filePath,
      {Map<String, String> params}) async {
    final FileInfo fileInfo = _generateFileInfo(filePath, fileKey);

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
      final Response response = await _mkfile(fileInfo, finishedCtxList);
      if (response == null) {
        streamSubscription.cancel();
        throw Exception('No Response');
      }
      final String hash = response.data['hash'];
      fileInfo.hash = hash;
    });
  }

  FileInfo _generateFileInfo(String path, String fileKey) {
    final File file = File(path);
    if (!file.existsSync())
      throw Exception('[QiniuUploader] putFile() file no exists');
    final int size = file.lengthSync();
    final String mimeType = lookupMimeType(path);
    final String ext = extension(path);
    final String key = fileKey ?? uuid.v4() + ext;
    final FileInfo fileInfo = FileInfo(
        domain: domain,
        file: file,
        size: size,
        path: path,
        mimeType: mimeType,
        ext: ext,
        key: key);
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

  Future<Response> _mkfile(FileInfo fileInfo, List<String> ctxList,
      {Map<String, String> params}) async {
    try {
      String url = '$domain';
      url += '/mkfile/${fileInfo.size}';
      url += '/key/${_urlsafeBase64Encode(fileInfo.key)}';
      url += '/mimeType/${_urlsafeBase64Encode(fileInfo.mimeType)}';
      if (params != null) {
        url = _handleParams(params);
      }
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

  _handleParams(Map<String, String> params, {String uri, FormData formData}) {
    params.forEach((String key, String value) {
      if (key.startsWith('x:')) {
        if (uri != null) {
          uri += '/$key/${_urlsafeBase64Encode(value)}';
        } else if (formData != null) {
          formData.add(key, value);
        }
      }
    });
    if (uri != null) return uri;
    if (formData != null) return formData;
  }
}

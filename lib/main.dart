import 'dart:io';

import 'package:path/path.dart' show join, current;
import 'package:yaml/yaml.dart';
import 'package:qiniu_dart/resume_uploader.dart';

Future<void> main(args) async {
  final File file = File('env.yaml');
  final String envString = file.readAsStringSync();
  final Map doc = loadYaml(envString);

  final String token = doc['UPLOAD_TOKEN'];
  final QiniuUploader qiniuUploader = QiniuUploader(token: token);

  // final String imagePath = join(current, 'assets/lexus-lx570.jpg');
  // await qiniuUploader.formUpload('lexus-lx570.jpg', imagePath);

  final String videoPath = join(current, 'assets/screenrecord.mp4');
  await qiniuUploader.resumeUpload('screenrecord.mp4', videoPath);
}

import 'dart:io';

void main(args) {
  print('hello uploader');
  String assetPath =
      '/Users/tong/Documents/wedding/qiniu_dart/assets/screenrecord.mp4';
  File assetFile = File(assetPath);
  assetFile.openRead();
}

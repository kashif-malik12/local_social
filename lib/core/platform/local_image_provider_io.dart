import 'dart:io' show File;

import 'package:flutter/material.dart';

ImageProvider localImageProvider(String path) => FileImage(File(path));

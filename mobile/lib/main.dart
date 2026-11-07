import 'package:flutter/material.dart';

import 'app.dart';
import 'core/network/api_config.dart';
import 'core/storage/app_state_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiConfig.initialize();
  await AppStateStorage.initTheme();
  runApp(const KKRTCApp());
}

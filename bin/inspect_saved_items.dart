// ignore_for_file: avoid_print

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:postgres/postgres.dart';
import 'package:smartpoc/env_config.dart';

void main() async {
  await dotenv.load(fileName: '.env');
  final host = EnvConfig.dbHost;
  final port = EnvConfig.dbPort;
  final database = EnvConfig.dbName;
  final username = EnvConfig.dbUsername;
  final password = EnvConfig.dbPassword;

  if (host.isEmpty || password.isEmpty) {
    print('Error: DB credentials missing in .env file.');
    return;
  }

  final conn = await Connection.open(
    Endpoint(
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
    ),
    settings: const ConnectionSettings(sslMode: SslMode.require),
  );

  print('=== SAVED_ITEMS TABLE ===');
  final items = await conn.execute('SELECT user_id, name, price, description, url, image, created_at FROM saved_items ORDER BY created_at DESC;');
  if (items.isEmpty) {
    print('No items in saved_items table yet.');
  } else {
    for (final row in items) {
      print('User ID: ${row[0]} | Name: "${row[1]}" | Price: ${row[2]} | Image: ${row[5]} | Created: ${row[6]}');
    }
  }

  await conn.close();
}

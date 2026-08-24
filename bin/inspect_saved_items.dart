import 'package:postgres/postgres.dart';

void main() async {
  final conn = await Connection.open(
    Endpoint(
      host: 'glassdata-postgres.c5e2qgumyvsg.ap-south-1.rds.amazonaws.com',
      port: 5432,
      database: 'glassdatadb',
      username: 'glassdata_admin',
      password: 'glassdatadb1234',
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

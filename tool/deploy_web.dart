// Builds the web app against the cloud backend and publishes it to Netlify.
//
//   dart run tool/deploy_web.dart
//
// Reads SUPABASE_URL and SUPABASE_ANON_KEY from deploy.env (not in git; copy
// deploy.env.example). Needs the Netlify CLI: npm install -g netlify-cli,
// then `netlify login` once. Never put the service_role key in deploy.env.
import 'dart:io';

Future<int> run(String command, List<String> args) async {
  stdout.writeln('\n> $command ${args.join(' ')}');
  final p = await Process.start(
    command,
    args,
    mode: ProcessStartMode.inheritStdio,
    runInShell: true,
  );
  return p.exitCode;
}

Future<void> main(List<String> args) async {
  final file = File('deploy.env');
  if (!file.existsSync()) {
    stderr.writeln(
      'deploy.env not found. Copy deploy.env.example to '
      'deploy.env and fill it in. Run this from the project folder.',
    );
    exit(1);
  }
  final env = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#') || !t.contains('=')) continue;
    final i = t.indexOf('=');
    env[t.substring(0, i).trim()] = t.substring(i + 1).trim();
  }
  final url = env['SUPABASE_URL'] ?? '';
  final key = env['SUPABASE_ANON_KEY'] ?? '';
  if (url.isEmpty || key.isEmpty) {
    stderr.writeln('deploy.env must set SUPABASE_URL and SUPABASE_ANON_KEY.');
    exit(1);
  }
  if (key.contains('service_role') || key.startsWith('sb_secret_')) {
    stderr.writeln('That looks like a secret key. Use the publishable key.');
    exit(1);
  }

  var code = await run('flutter', [
    'build',
    'web',
    '--release',
    // Serve the engine from our own site, not a third-party CDN.
    '--no-web-resources-cdn',
    '--dart-define=SUPABASE_URL=$url',
    '--dart-define=SUPABASE_ANON_KEY=$key',
  ]);
  if (code != 0) exit(code);

  // `--draft` publishes a preview link instead of the live site.
  final draft = args.contains('--draft');
  code = await run('netlify', [
    'deploy',
    if (!draft) '--prod',
    '--dir',
    'build/web',
    '--no-build',
  ]);
  exit(code);
}

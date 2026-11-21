/// Each kind of user has its own link. Car owners stay on the main address
/// and never see the trade side.
enum Portal {
  owner('/', 'Fundi'),
  admin('/admin', 'Fundi admin'),
  garage('/garage', 'Fundi for mechanics and garages'),
  parts('/parts', 'Fundi parts shops');

  const Portal(this.path, this.title);

  /// Where the portal lives on the site, for example `/admin`.
  final String path;

  /// Shown in the browser tab.
  final String title;

  /// The portal for a web address path. Unknown paths open the owner app.
  static Portal fromPath(String path) {
    final first = path
        .split('/')
        .firstWhere((s) => s.isNotEmpty, orElse: () => '')
        .toLowerCase();
    return switch (first) {
      'admin' => Portal.admin,
      'garage' || 'mechanic' || 'mechanics' => Portal.garage,
      'parts' || 'shop' => Portal.parts,
      _ => Portal.owner,
    };
  }
}

import 'package:flutter/material.dart';

import '../data/account_repository.dart';
import '../data/admin_repository.dart';
import '../models/admin_request.dart';
import '../models/trade.dart';
import 'admin_overview.dart';
import 'admin_requests.dart';
import 'admin_screen.dart';
import 'theme.dart';

/// One search across the console: mechanics and garages (any status),
/// parts shops and requests. A tap opens the right section on that item.
class AdminSearchResults extends StatelessWidget {
  const AdminSearchResults({
    super.key,
    required this.query,
    required this.data,
    required this.onListing,
    required this.onShop,
    required this.onRequest,
  });
  final String query;
  final Future<AdminSnapshot> data;
  final ValueChanged<AdminListing> onListing;
  final ValueChanged<PartsShop> onShop;
  final ValueChanged<AdminRequest> onRequest;

  static const _limit = 8;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AdminSnapshot>(
      future: data,
      builder: (context, snap) {
        if (snap.hasError) {
          return const AdminEmpty(
            icon: Icons.search_off,
            title: 'Search is not working right now',
            body: 'Check the connection and try again.',
          );
        }
        final s = snap.data;
        if (s == null) return const Center(child: CircularProgressIndicator());
        final listings = [
          for (final l in [...s.waiting, ...s.live, ...s.paused])
            if (adminSearchMatches(
              query,
              texts: [l.name, l.area],
              phones: [l.phone],
            ))
              l,
        ];
        final shops = [
          for (final p in s.shops)
            if (adminSearchMatches(
              query,
              texts: [p.name, p.area],
              phones: [p.phone],
            ))
              p,
        ];
        final requests = sortForAdmin(
          s.requests.where((r) => r.matches(query)),
        );
        if (listings.isEmpty && shops.isEmpty && requests.isEmpty) {
          return AdminEmpty(
            icon: Icons.search_off,
            title: 'Nothing matches "${query.trim()}"',
            body:
                'Try part of a name, an area, the last digits of a phone '
                'number, or a request reference like ${s.requests.isEmpty ? 'A1F300' : s.requests.first.ref}.',
          );
        }
        return ListView(
          key: const Key('admin-search-results'),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            if (listings.isNotEmpty)
              _Group('Mechanics and garages', listings.length, [
                for (final l in listings.take(_limit))
                  _Hit(
                    key: Key('hit-listing-${l.id}'),
                    leading: AdminAvatar(l.name, size: 36),
                    title: l.name,
                    detail:
                        '${l.area} · ${l.phone} · ${switch (l.status) {
                          ListingStatus.pending => 'waiting for checks',
                          ListingStatus.approved => 'live',
                          ListingStatus.suspended => 'paused',
                        }}',
                    onTap: () => onListing(l),
                  ),
              ]),
            if (shops.isNotEmpty)
              _Group('Parts shops', shops.length, [
                for (final p in shops.take(_limit))
                  _Hit(
                    key: Key('hit-shop-${p.id}'),
                    leading: const _Square(Icons.storefront_outlined),
                    title: p.name,
                    detail:
                        '${p.area} · ${p.phone}${p.active ? '' : ' · paused'}',
                    onTap: () => onShop(p),
                  ),
              ]),
            if (requests.isNotEmpty)
              _Group('Requests', requests.length, [
                for (final r in requests.take(_limit))
                  _Hit(
                    key: Key('hit-request-${r.id}'),
                    leading: const _Square(Icons.forum_outlined),
                    title: r.problem,
                    detail:
                        '${r.ref} · ${r.area ?? 'Unknown'} · ${r.providerName ?? 'nobody yet'}',
                    trailing: StagePill(r.stage),
                    onTap: () => onRequest(r),
                  ),
              ]),
          ],
        );
      },
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.title, this.count, this.children);
  final String title;
  final int count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              count > AdminSearchResults._limit
                  ? '$title · first ${AdminSearchResults._limit} of $count'
                  : '$title · $count',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: muted,
              ),
            ),
          ),
          ...children,
        ],
      ),
    ),
  );
}

class _Hit extends StatelessWidget {
  const _Hit({
    super.key,
    required this.leading,
    required this.title,
    required this.detail,
    required this.onTap,
    this.trailing,
  });
  final Widget leading;
  final String title;
  final String detail;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFEEF0EC))),
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: muted),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: muted),
        ],
      ),
    ),
  );
}

class _Square extends StatelessWidget {
  const _Square(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: tint,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, size: 18, color: forest),
  );
}

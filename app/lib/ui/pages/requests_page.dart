import 'package:console_ui/console_ui.dart';
import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../state/scope.dart';
import '../common.dart';
import '../nav.dart';
import '../request_list.dart';

class RequestsPage extends StatefulWidget {
  const RequestsPage({super.key});
  @override
  State<RequestsPage> createState() => _RequestsPageState();
}

class _RequestsPageState extends State<RequestsPage> {
  String _filter = 'active';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (app.seerrConn != Conn.ok) {
      return PageBody(
        children: [
          ConsolePanel(
            title: 'Requests',
            child: EmptyState(
              title: app.seerrConn == Conn.failed ? "Can't reach Seerr" : "Seerr isn't set up",
              body: app.seerrError ?? 'Connect Seerr in Settings to see and make requests.',
              action: ConsoleButton(label: 'Open Settings', onPressed: () => ShellNav.of(context).go(const SettingsDest())),
            ),
          ),
        ],
      );
    }
    final rows = app.requests;
    // Titles not out on streaming yet get their own panel, soonest first, undated last.
    final waiting = (rows ?? const <RequestRow>[]).where((r) => r.state.notOnStreaming).toList()
      ..sort((a, b) => (a.state.wait!.date ?? DateTime(9999)).compareTo(b.state.wait!.date ?? DateTime(9999)));
    final shown = rows
        ?.where((r) => !r.state.notOnStreaming)
        .where(
          (r) => switch (_filter) {
            'active' => r.state.isActive,
            'available' => r.state.label == 'Available',
            _ => true,
          },
        )
        .toList();
    return PageBody(
      children: [
        ConsolePanel(
          title: 'Requests',
          meta: app.downloadingCount > 0 ? Text('↓ ${app.downloadingCount} Downloading', style: ConsoleText.small.copyWith(color: context.c.chartDownload)) : null,
          trailing: ConsoleSegmented<String>(options: const [('active', 'In Progress'), ('available', 'Available'), ('all', 'All')], value: _filter, onChanged: (v) => setState(() => _filter = v)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (shown == null)
                const LoadingNote()
              else if (shown.isEmpty)
                EmptyState(
                  title: _filter == 'active' ? (waiting.isEmpty ? 'No open requests' : 'Nothing downloading') : 'Nothing here yet',
                  body: _filter == 'active' && waiting.isNotEmpty ? 'Your other requests are waiting for a streaming release, below.' : "Search for a title that isn't in Plex to request it.",
                )
              else
                RequestList(rows: shown),
              const SizedBox(height: Space.space3),
              Text("Progress refreshes every 10 seconds from Seerr's download tracking.", style: ConsoleText.caption.copyWith(color: context.c.text300)),
            ],
          ),
        ),
        if (_filter != 'available' && waiting.isNotEmpty)
          ConsolePanel(
            title: 'Not on Streaming Yet',
            meta: Text('${waiting.length}', style: ConsoleText.small.copyWith(color: context.c.text300)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RequestList(rows: waiting),
                const SizedBox(height: Space.space3),
                Text(
                  "Requested, but not out on streaming or digital yet, so there's nothing to download. Seerr picks them up once they're out. Dates are from TMDB via Seerr.",
                  style: ConsoleText.caption.copyWith(color: context.c.text300),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

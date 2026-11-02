import 'format.dart';
import 'seerr/seerr_models.dart';
import 'streaming_date.dart';

enum Tone { success, warning, danger, info, neutral }

/// What a request looks like to the user right now.
class RequestState {
  const RequestState({required this.label, required this.tone, this.progress, this.detail, required this.requestable, this.waiting = false, this.wait});

  final String label;
  final Tone tone;

  /// 0..1 while downloading.
  final double? progress;

  /// "18m left · done 7:42 PM · 3.3 GB of 7.8 GB"
  final String? detail;

  /// The user can still press Request.
  final bool requestable;

  /// Approved, no download yet: show an indeterminate bar.
  final bool waiting;

  /// Requested, but not out on streaming yet, so there's nothing to download.
  final StreamingWait? wait;
  bool get notOnStreaming => wait != null;

  bool get isActive => label != 'Available' && label != 'Declined' && label != 'Failed';
  bool get isDownloading => label == 'Downloading' || label == 'Queued';
}

/// Turns Seerr's request status, media status and live download stats into one state.
RequestState requestStateOf(SeerrMediaInfo? media, [SeerrRequest? request, DateTime? now]) {
  final req = request ?? (media?.requests.isNotEmpty == true ? media!.requests.first : null);
  final downloads = media?.downloads ?? const <DownloadStatus>[];

  if (media?.status == MediaStatus.available) {
    return const RequestState(label: 'Available', tone: Tone.success, progress: 1, requestable: false);
  }

  if (downloads.isNotEmpty) {
    final size = downloads.fold<double>(0, (a, d) => a + d.size);
    final left = downloads.fold<double>(0, (a, d) => a + d.sizeLeft);
    final progress = size > 0 ? ((size - left) / size).clamp(0.0, 1.0) : 0.0;
    final etas = downloads.map((d) => d.estimatedCompletionTime).whereType<DateTime>().toList()..sort();
    final eta = etas.isEmpty ? null : etas.last; // done when the last file lands
    final until = formatTimeUntil(eta, now: now);
    final parts = [
      until != null ? '$until left' : 'Estimating time',
      if (eta != null) 'done ${formatClock(eta, now: now)}',
      if (size > 0) '${formatBytes(size - left)} of ${formatBytes(size)}',
      if (downloads.length > 1) '${downloads.length} files',
    ];
    final stalled = downloads.every((d) => RegExp('warn|stall|paused|queued', caseSensitive: false).hasMatch(d.status ?? ''));
    return RequestState(label: stalled ? 'Queued' : 'Downloading', tone: stalled ? Tone.warning : Tone.info, progress: progress, detail: parts.join(' · '), requestable: false);
  }

  if (media?.status == MediaStatus.partiallyAvailable) {
    return const RequestState(label: 'Partially Available', tone: Tone.success, requestable: true);
  }
  if (req?.status == RequestStatus.declined) return const RequestState(label: 'Declined', tone: Tone.danger, requestable: true);
  if (req?.status == RequestStatus.failed) {
    return const RequestState(label: 'Failed', tone: Tone.danger, detail: 'Seerr could not send this to the downloader', requestable: true);
  }
  if (req?.status == RequestStatus.pending || media?.status == MediaStatus.pending) {
    return const RequestState(label: 'Pending Approval', tone: Tone.warning, detail: 'Waiting for an admin to approve', requestable: false);
  }
  if (media?.status == MediaStatus.processing || req?.status == RequestStatus.approved) {
    return const RequestState(label: 'Requested', tone: Tone.info, progress: 0, waiting: true, detail: 'Searching for a release', requestable: false);
  }
  return const RequestState(label: 'Not Requested', tone: Tone.neutral, requestable: true);
}

/// [requestStateOf], and with the title's Seerr [details] in hand, a request still
/// searching for a title that isn't out on streaming yet says so (with the date) instead
/// of showing a bar. Once anything downloads, or the date passes, it's an ordinary request.
RequestState requestStateWith(SeerrMediaInfo? media, SeerrRequest? request, SeerrResult? details, {DateTime? now}) {
  final base = requestStateOf(media, request, now);
  if (base.label != 'Requested') return base;
  final req = request ?? (media?.requests.isNotEmpty == true ? media!.requests.first : null);
  final wait = streamingWaitOf(details, seasons: req?.seasonNumbers ?? const [], now: now);
  if (wait == null) return base;
  final until = wait.until(now: now);
  return RequestState(
    label: notOnStreamingLabel,
    tone: Tone.neutral,
    detail: [wait.headline, ?until].join(' · '),
    requestable: false,
    wait: wait,
  );
}

const notOnStreamingLabel = 'Not on Streaming Yet';

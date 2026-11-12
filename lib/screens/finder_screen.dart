import 'package:flutter/material.dart';
import 'package:theme/theme.dart';

import '../seek/finder_controller.dart';
import '../seek/models.dart';
import '../seek/proximity.dart';
import '../seek/seek_platform.dart';
import 'kind_icon.dart';

/// The hot and cold meter for one device. The scan runs only while this screen is open.
class FinderScreen extends StatefulWidget {
  const FinderScreen({super.key, required this.platform, required this.device});

  final SeekPlatform platform;
  final SeekDevice device;

  @override
  State<FinderScreen> createState() => _FinderScreenState();
}

class _FinderScreenState extends State<FinderScreen> {
  late final FinderController _finder = FinderController(widget.platform, widget.device);
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _finder.start();
    // Never keep scanning (or beeping) when the app is in the background.
    _lifecycle = AppLifecycleListener(
      onHide: () {
        if (mounted) Navigator.of(context).maybePop();
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _finder.dispose();
    super.dispose();
  }

  UiStatus _statusFor(double heat) {
    if (heat >= 0.7) return UiStatus.danger;
    if (heat >= 0.3) return UiStatus.warning;
    return UiStatus.info;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _finder,
      builder: (context, _) {
        final d = widget.device;
        return UiScaffold(
          appBar: UiAppBar(title: d.title),
          scrollable: true,
          body: UiColumn(
            gap: UiSpace.lg,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _meter(context),
              _alerts(),
              UiListGroup(
                header: 'Alerts',
                footer: 'The beep and the vibration speed up as you get closer.',
                children: [
                  UiSwitchTile(
                    'Beep',
                    icon: Icons.volume_up_rounded,
                    value: _finder.beepOn,
                    onChanged: (v) => _finder.beepOn = v,
                  ),
                  UiSwitchTile(
                    'Vibrate',
                    icon: Icons.vibration_rounded,
                    value: _finder.vibrateOn,
                    onChanged: (v) => _finder.vibrateOn = v,
                  ),
                ],
              ),
              if (d.bonded && d.kind.isAudio) _playSound(),
              UiAlert(
                _tip(d),
                title: 'Tips',
                icon: Icons.lightbulb_outline_rounded,
              ),
            ],
          ),
        );
      },
    );
  }

  String _tip(SeekDevice d) {
    final common = 'Walk slowly and watch the meter: a stronger signal means you are closer. '
        'Turning around or putting your body between you and the device lowers it.';
    if (d.kind == DeviceKind.earbuds) {
      return 'Earbuds often only advertise when they are out of the case, so open the case lid. '
          'A bud that sits in a closed case may not be found at all. $common';
    }
    return common;
  }

  Widget _meter(BuildContext context) {
    final c = context.colors;
    final heat = _finder.heat;
    final state = _finder.state;
    final tracking = state == FinderState.tracking;
    final meters = _finder.distanceMeters;

    final String headline = switch (state) {
      FinderState.searching => 'Searching',
      FinderState.lost => 'Signal lost',
      FinderState.tracking => _finder.heatLabel.label,
    };
    final trend = _finder.trend;
    final (IconData trendIcon, String trendText) = switch (trend) {
      Trend.closer => (Icons.arrow_upward_rounded, 'Getting closer'),
      Trend.farther => (Icons.arrow_downward_rounded, 'Getting farther'),
      Trend.steady => (Icons.drag_handle_rounded, tracking ? 'Steady' : '-'),
    };

    return UiCard(
      child: Column(
        children: [
          UiGauge(
            value: heat,
            size: 280,
            status: tracking ? _statusFor(heat) : UiStatus.neutral,
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(iconForKind(widget.device.kind), color: c.textMuted, size: 28),
                const SizedBox(height: UiSpace.xs),
                Text(headline, style: context.text.headlineSmall, textAlign: TextAlign.center),
                if (_finder.smoothedRssi != null && tracking)
                  Text('${_finder.smoothedRssi!.round()} dBm', style: context.text.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: UiSpace.md),
          UiKeyValue('Distance (approx.)', tracking && meters != null ? formatDistance(meters) : '-'),
          UiKeyValue.custom(
            'Direction',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  trendIcon,
                  size: 18,
                  color: trend == Trend.closer
                      ? c.tone(UiStatus.success).color
                      : trend == Trend.farther
                          ? c.tone(UiStatus.danger).color
                          : c.textMuted,
                ),
                const SizedBox(width: UiSpace.xs),
                Text(trendText),
              ],
            ),
          ),
          UiKeyValue('Last heard', _finder.secondsSinceSeen == null ? 'Not yet' : '${_finder.secondsSinceSeen} s ago'),
        ],
      ),
    );
  }

  Widget _alerts() {
    final state = _finder.state;
    if (_finder.error != null) {
      return UiAlert(_finder.error!, status: UiStatus.danger);
    }
    if (state == FinderState.lost) {
      return UiAlert(
        'Not seen for ${_finder.secondsSinceSeen} s. Walk around, move away from walls and metal, '
        'and make sure the device is on and out of its case.',
        title: 'Signal lost',
        status: UiStatus.warning,
      );
    }
    if (state == FinderState.searching) {
      return const UiAlert(
        'Waiting for the first signal. Open the case lid of earbuds, and wake a watch or band.',
        title: 'Searching',
        status: UiStatus.info,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _playSound() {
    return UiCard(
      child: UiColumn(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Play sound', style: context.text.titleMedium),
          Text(
            'Plays a loud tone on your connected Bluetooth audio, so you can hear the device. '
            'Works only while it is connected to this phone. Turn the media volume up first. '
            'Stops by itself after 20 seconds.',
            style: context.text.bodySmall,
          ),
          UiButton(
            _finder.tonePlaying ? 'Stop sound' : 'Play sound on ${widget.device.title}',
            icon: _finder.tonePlaying ? Icons.stop_rounded : Icons.volume_up_rounded,
            variant: _finder.tonePlaying ? UiButtonVariant.danger : UiButtonVariant.soft,
            onPressed: _finder.toggleTone,
          ),
        ],
      ),
    );
  }
}

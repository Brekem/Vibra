import 'package:flutter/material.dart';

import '../audio/recommendations.dart';
import '../audio/spectrum_analyzer.dart';
import '../models/frequency_peak.dart';
import '../scanner_controller.dart';
import 'app_colors.dart';
import 'widgets/spectrum_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.controller});

  /// Permite inyectar un controlador (útil en pruebas).
  final ScannerController? controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final ScannerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? ScannerController();
    _controller.addListener(_showPendingMessage);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_showPendingMessage);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // En segundo plano el audio continúa gracias al servicio en primer plano;
    // solo se detiene todo cuando la app se cierra definitivamente.
    if (state == AppLifecycleState.detached) {
      _controller.stopAll();
    }
  }

  void _showPendingMessage() {
    final message = _controller.takeMessage();
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.green,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            const Text(
              'Frequency Scanner',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Acerca de',
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () => _showAbout(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            final c = _controller;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                _ScanButton(controller: c),
                const SizedBox(height: 16),
                _CycleCard(controller: c),
                const SizedBox(height: 16),
                _DominantCard(controller: c),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Espectro en tiempo real',
                  trailing: Text(
                    'Δf ${c.analyzer.binHz.toStringAsFixed(1)} Hz',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                  child: SpectrumView(controller: c),
                ),
                const SizedBox(height: 16),
                _PeakListCard(controller: c),
                const SizedBox(height: 16),
                _SuggestionsCard(controller: c),
                const SizedBox(height: 16),
                _ToneCard(controller: c),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('Frequency Scanner'),
        content: const Text(
          'Herramienta técnica de análisis de audio.\n\n'
          '• Captura el micrófono a 44,1 kHz y calcula una FFT de 8192 puntos '
          'con ventana de Hann y 75 % de solapamiento.\n'
          '• Los niveles se expresan en dBFS (0 dB = escala completa del '
          'micrófono). El micrófono del teléfono no está calibrado, por lo que '
          'los valores son relativos.\n'
          '• El generador produce tonos senoidales puros entre 20 Hz y 20 kHz. '
          'La respuesta real depende del altavoz del dispositivo.\n\n'
          'Usa volúmenes moderados para proteger tu audición y tus altavoces.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cerrar')),
        ],
      ),
    );
  }
}

String formatHz(double hz) =>
    hz >= 1000 ? '${(hz / 1000).toStringAsFixed(2)} kHz' : '${hz.toStringAsFixed(1)} Hz';

String formatDb(double db) => db <= SpectrumAnalyzer.minDb ? '— dB' : '${db.toStringAsFixed(1)} dB';

class _ScanButton extends StatelessWidget {
  const _ScanButton({required this.controller});

  final ScannerController controller;

  @override
  Widget build(BuildContext context) {
    final scanning = controller.isScanning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: controller.isBusy || controller.isCycleActive ? null : controller.toggleScan,
          style: scanning ? FilledButton.styleFrom(backgroundColor: AppColors.greenDark) : null,
          icon: controller.isBusy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Icon(scanning ? Icons.stop_rounded : Icons.mic_rounded),
          label: Text(scanning ? 'Detener escaneo' : 'Escanear'),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scanning ? AppColors.greenLight : AppColors.border,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              scanning
                  ? 'Analizando · nivel ${controller.levelDb.toStringAsFixed(1)} dBFS'
                  : 'Micrófono detenido',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ],
        ),
      ],
    );
  }
}

String formatDuration(Duration d) {
  final m = d.inMinutes.toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// Modo continuo: escaneo y reproducción alternados de forma indefinida.
class _CycleCard extends StatelessWidget {
  const _CycleCard({required this.controller});

  final ScannerController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final active = c.isCycleActive;
    final scanning = c.cyclePhase == CyclePhase.scanning;
    final scanMin = c.cycleScanDuration.inMinutes;
    final playMin = c.cyclePlayDuration.inMinutes;
    final phaseTotal = scanning ? c.cycleScanDuration : c.cyclePlayDuration;
    final progress = active && phaseTotal.inMilliseconds > 0
        ? 1 - c.phaseRemaining.inMilliseconds / phaseTotal.inMilliseconds
        : 0.0;

    return _SectionCard(
      title: 'Modo continuo',
      trailing: active
          ? _StatusChip(text: 'Ciclo ${c.cycleCount}', color: AppColors.green)
          : const _StatusChip(text: 'Inactivo', color: AppColors.textMuted),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Repite sin fin: $scanMin min de escaneo y $playMin min reproduciendo la '
            'frecuencia sugerida en ese escaneo (por defecto, la frecuencia que menos '
            'está presente en tu ambiente).',
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _PhaseStep(
                icon: Icons.mic_rounded,
                label: 'Escaneo · $scanMin min',
                active: active && scanning,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.textMuted),
              ),
              _PhaseStep(
                icon: Icons.graphic_eq_rounded,
                label: 'Reproducción · $playMin min',
                active: active && !scanning,
              ),
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.all_inclusive_rounded, size: 18, color: AppColors.green),
              ),
            ],
          ),
          if (active) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    scanning ? 'Escaneando…' : 'Reproduciendo ${formatHz(c.toneFrequency)}',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textDark),
                  ),
                ),
                Text(
                  formatDuration(c.phaseRemaining),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.greenDark,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: AppColors.greenTint,
                color: AppColors.green,
              ),
            ),
          ],
          const SizedBox(height: 14),
          active
              ? OutlinedButton.icon(
                  onPressed: c.stopAll,
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('Detener modo continuo'),
                )
              : FilledButton.icon(
                  onPressed: c.isBusy ? null : c.startCycle,
                  icon: const Icon(Icons.loop_rounded),
                  label: const Text('Iniciar modo continuo'),
                ),
        ],
      ),
    );
  }
}

class _PhaseStep extends StatelessWidget {
  const _PhaseStep({required this.icon, required this.label, required this.active});

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.green : AppColors.greenTint,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: active ? Colors.white : AppColors.greenDark),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : AppColors.greenDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DominantCard extends StatelessWidget {
  const _DominantCard({required this.controller});

  final ScannerController controller;

  @override
  Widget build(BuildContext context) {
    final peak = controller.dominant;
    final note = peak == null ? null : MusicalNote.nearest(peak.frequency);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.green, AppColors.greenDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'FRECUENCIA DOMINANTE',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: peak == null ? '—' : peak.frequency.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(
                    text: ' Hz',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              style: const TextStyle(
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(
                icon: Icons.volume_up_rounded,
                text: peak == null ? 'Intensidad —' : '${peak.db.toStringAsFixed(1)} dBFS',
              ),
              _Pill(
                icon: Icons.music_note_rounded,
                text: note == null
                    ? 'Nota —'
                    : '${note.name} ${note.cents >= 0 ? '+' : ''}${note.cents.toStringAsFixed(0)} ct',
              ),
              _Pill(
                icon: Icons.stacked_bar_chart_rounded,
                text: '${controller.peaks.length} picos',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.greenTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
      ),
    );
  }
}

class _PeakListCard extends StatelessWidget {
  const _PeakListCard({required this.controller});

  final ScannerController controller;

  @override
  Widget build(BuildContext context) {
    final peaks = controller.peaks;
    return _SectionCard(
      title: 'Frecuencias detectadas',
      trailing: const Text('Hz · dBFS', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
      child: peaks.isEmpty
          ? const _EmptyHint(
              'Aún no hay frecuencias predominantes. '
              'Inicia el escaneo cerca de una fuente de sonido.',
            )
          : Column(
              children: [
                for (var i = 0; i < peaks.length; i++)
                  _PeakRow(
                    rank: i + 1,
                    peak: peaks[i],
                    onPlay: controller.isCycleActive
                        ? null
                        : () => controller.playTone(peaks[i].frequency),
                  ),
              ],
            ),
    );
  }
}

class _PeakRow extends StatelessWidget {
  const _PeakRow({required this.rank, required this.peak, required this.onPlay});

  final int rank;
  final FrequencyPeak peak;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final level = ((peak.db + 100) / 100).clamp(0.0, 1.0);
    final note = MusicalNote.nearest(peak.frequency);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: rank == 1 ? AppColors.green : AppColors.greenSoft,
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: rank == 1 ? Colors.white : AppColors.greenDark,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      formatHz(peak.frequency),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (note != null)
                      Text(
                        note.name,
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    const Spacer(),
                    Text(
                      formatDb(peak.db),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: level,
                    minHeight: 6,
                    backgroundColor: AppColors.greenTint,
                    color: AppColors.green,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Reproducir ${formatHz(peak.frequency)}',
            onPressed: onPlay,
            icon: const Icon(Icons.play_circle_fill_rounded, color: AppColors.green),
          ),
        ],
      ),
    );
  }
}

class _SuggestionsCard extends StatelessWidget {
  const _SuggestionsCard({required this.controller});

  final ScannerController controller;

  @override
  Widget build(BuildContext context) {
    final items = controller.recommendations;
    return _SectionCard(
      title: 'Frecuencias de prueba sugeridas',
      child: items.isEmpty
          ? const _EmptyHint(
              'Escanea para calcular la frecuencia ausente en tu ambiente y '
              'otras frecuencias relacionadas con el pico dominante.',
            )
          : Column(
              children: [
                for (var i = 0; i < items.length; i++)
                  _SuggestionTile(
                    item: items[i],
                    selected: i == controller.selectedRecommendation,
                    onTap: () => controller.selectRecommendation(i),
                  ),
              ],
            ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({required this.item, required this.selected, required this.onTap});

  final TestFrequency item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected ? AppColors.greenSoft : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? AppColors.green : AppColors.border),
            ),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: selected ? AppColors.green : AppColors.textMuted,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.detail,
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatHz(item.frequency),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.greenDark,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToneCard extends StatelessWidget {
  const _ToneCard({required this.controller});

  final ScannerController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final suggested = c.suggested;
    return _SectionCard(
      title: 'Generador de tonos',
      trailing: c.isPlaying
          ? const _StatusChip(text: 'Sonando', color: AppColors.green)
          : const _StatusChip(text: 'En pausa', color: AppColors.textMuted),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.greenTint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Text(
                  formatHz(c.toneFrequency),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: AppColors.greenDark,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const Text(
                  'Senoidal pura',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final d in const [-10.0, -1.0, 1.0, 10.0])
                      _StepButton(delta: d, onPressed: () => c.adjustFrequency(d)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.volume_down_rounded, color: AppColors.textMuted),
              Expanded(
                child: Slider(
                  value: c.volume,
                  onChanged: c.setVolume,
                  label: '${(c.volume * 100).round()} %',
                  divisions: 100,
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '${(c.volume * 100).round()} %',
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: AppColors.textDark, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: c.isCycleActive ? null : c.togglePlaySuggested,
            icon: Icon(c.isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded),
            label: Text(
              c.isPlaying
                  ? 'Detener tono'
                  : suggested == null
                  ? 'Reproducir frecuencia sugerida'
                  : 'Reproducir frecuencia sugerida · ${formatHz(suggested.frequency)}',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: c.isCycleActive ? null : c.toggleTone,
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            icon: Icon(c.isPlaying ? Icons.pause_rounded : Icons.tune_rounded),
            label: Text(c.isPlaying ? 'Pausar' : 'Reproducir ${formatHz(c.toneFrequency)}'),
          ),
          const SizedBox(height: 10),
          const Text(
            'Empieza con un volumen bajo. Los altavoces de los teléfonos suelen '
            'reproducir mal por debajo de ~150 Hz. Si escaneas mientras suena un '
            'tono, el micrófono también lo captará. El sonido sigue reproduciéndose '
            'en segundo plano; puedes detenerlo desde la notificación.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.delta, required this.onPressed});

  final double delta;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 40),
        backgroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Text('${delta > 0 ? '+' : ''}${delta.toStringAsFixed(0)} Hz'),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

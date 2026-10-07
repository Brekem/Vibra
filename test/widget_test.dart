import 'package:flutter_test/flutter_test.dart';
import 'package:frequency_scanner/main.dart';

void main() {
  testWidgets('La pantalla principal muestra los controles', (tester) async {
    await tester.pumpWidget(const FrequencyScannerApp());
    expect(find.text('Frequency Scanner'), findsOneWidget);
    expect(find.text('Escanear'), findsOneWidget);
    expect(find.text('FRECUENCIA DOMINANTE'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Iniciar modo continuo'), 200);
    expect(find.text('Modo continuo'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Frecuencias detectadas'), 200);
    expect(find.text('Frecuencias detectadas'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Reproducir frecuencia sugerida'), 200);
    expect(find.text('Reproducir frecuencia sugerida'), findsOneWidget);
  });
}

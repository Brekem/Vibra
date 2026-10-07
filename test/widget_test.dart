import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frequency_scanner/main.dart';

void main() {
  testWidgets('La pantalla principal muestra los controles', (tester) async {
    await tester.pumpWidget(const FrequencyScannerApp());
    final list = find.byType(Scrollable).first;
    expect(find.text('Frequency Scanner'), findsOneWidget);
    expect(find.text('Escanear'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Iniciar modo continuo'), 200, scrollable: list);
    expect(find.text('Modo continuo'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Usar'), 200, scrollable: list);
    expect(find.text('Ausente'), findsOneWidget);
    expect(find.text('Presente'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '50000');
    await tester.ensureVisible(find.text('Usar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usar'));
    await tester.pump();
    expect(find.text('Escribe un valor entre 20 y 20000 Hz'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('FRECUENCIA DOMINANTE'), 200, scrollable: list);
    expect(find.text('FRECUENCIA DOMINANTE'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Frecuencias detectadas'), 200, scrollable: list);
    expect(find.text('Frecuencias detectadas'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Reproducir frecuencia sugerida'),
      200,
      scrollable: list,
    );
    expect(find.text('Reproducir frecuencia sugerida'), findsOneWidget);
  });
}

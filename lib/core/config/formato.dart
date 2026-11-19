import 'package:intl/intl.dart';

/// Formatos regionales de Bolivia (separador de miles «.» y decimales «,»).
final _num0 = NumberFormat.decimalPattern('es_BO');
final _num1 = NumberFormat('#,##0.0', 'es_BO');
final _num2 = NumberFormat('#,##0.00', 'es_BO');
final _fecha = DateFormat('dd/MM/yyyy', 'es');
final _fechaHora = DateFormat('dd/MM/yyyy HH:mm', 'es');

double aNumero(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
DateTime? aFecha(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

/// Importe en bolivianos; el espacio no separable evita que «Bs» quede solo en una línea.
String bs(Object? v) => 'Bs\u00A0${_num2.format(aNumero(v))}';
String entero(Object? v) => _num0.format(aNumero(v).round());
String dec1(Object? v) => _num1.format(aNumero(v));
String dec2(Object? v) => _num2.format(aNumero(v));
String kg(Object? v) => '${_num1.format(aNumero(v))} kg';
String toneladas(Object? v) => '${_num2.format(aNumero(v))} t';
String fecha(Object? v) => aFecha(v) == null ? '—' : _fecha.format(aFecha(v)!);
String fechaHora(Object? v) => aFecha(v) == null ? '—' : _fechaHora.format(aFecha(v)!);
String isoDia(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// Nombres amigables de estados y tipos que vienen de la base.
const etiquetas = <String, String>{
  'fermentacion': 'En fermentación',
  'apto': 'Apto',
  'observado': 'Observado',
  'agotado': 'Agotado',
  'abierta': 'Abierta',
  'cerrada': 'Cerrada',
  'confirmado': 'Confirmado',
  'corregido': 'Corregido',
  'anulado': 'Anulado',
  'pendiente': 'Pendiente',
  'aprobada': 'Aprobada',
  'rechazada': 'Rechazada',
  'pagada': 'Pagada',
  'anulada': 'Anulada',
  'emitida': 'Emitida',
  'vigente': 'Vigente',
  'cotizacion': 'Cotización',
  'pedido': 'Pedido',
  'vendido': 'Vendido',
  'cancelado': 'Cancelado',
  'en_transito': 'En tránsito',
  'recibida': 'Recibida',
  'activo': 'Activo',
  'inactivo': 'Inactivo',
  'suspendido': 'Suspendido',
  'bloqueado': 'Bloqueado',
  'propio': 'Cosecha propia',
  'productor': 'Productor',
  'insumos': 'Insumos',
  'mayorista': 'Mayorista',
  'minorista': 'Minorista',
  'contado': 'Contado',
  'credito': 'Crédito',
  'tonelada': 'Por tonelada',
  'rollo': 'Por rollo',
  'insumo': 'Insumo',
  'efectivo': 'Efectivo',
  'transferencia': 'Transferencia',
  'qr': 'QR',
  'film_roto': 'Film roto',
  'manipuleo': 'Manipuleo',
  'traslado': 'Traslado',
  'conteo': 'Conteo',
  'integro': 'Íntegro',
  'danado': 'Dañado',
  'rol_privilegiado': 'Rol privilegiado',
  'correccion_pesaje': 'Corrección de pesaje',
  'merma': 'Baja de rollos (merma)',
  'ajuste': 'Ajuste por conteo',
  'cambio_precio': 'Cambio de precio',
  'producto_nuevo': 'Producto nuevo',
  'activar_proveedor': 'Activación de proveedor',
  'limite_credito': 'Límite de crédito',
  'compra': 'Compra',
  'nota_venta': 'Descuento o crédito en venta',
  'anulacion_venta': 'Anulación de venta',
  'anulacion_cobro': 'Anulación de cobro',
  'despacho_exceso': 'Despacho sobre la tolerancia',
  'restauracion': 'Restauración de respaldo',
  'oficina': 'Oficina',
  'centro_acopio': 'Centro de acopio',
};

String etiqueta(Object? v) => etiquetas['$v'] ?? '${v ?? '—'}';

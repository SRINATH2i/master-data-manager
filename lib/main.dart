import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String apiUrl = 'https://script.google.com/macros/s/AKfycbz2O-9fdR8_b3FexfaC8G6JoBm3Qm0v0aGfHzpz_ZgiupZuo1Yl-FrBfk3yobbwNbm-gQ/exec';

const List<String> statusOptions = [
  'Not sorted',
  'Selected',
  'Rejected',
  'Completed'
];

void main() {
  runApp(const MasterDataManagerApp());
}

class MasterDataManagerApp extends StatelessWidget {
  const MasterDataManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Master Data Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      ),
      home: const MainDataManagerScreen(),
    );
  }
}

class MainDataManagerScreen extends StatefulWidget {
  const MainDataManagerScreen({super.key});

  @override
  State<MainDataManagerScreen> createState() => _MainDataManagerScreenState();
}

class _MainDataManagerScreenState extends State<MainDataManagerScreen> {
  List<String> sheetNames = [];
  String selectedSheet = '';
  List<dynamic> rawGroups = [];
  List<dynamic> filteredGroups = [];
  bool isLoading = true;
  String saveStatus = '';
  Timer? _searchDebounce;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    fetchSheetNames();
  }

  Future<void> fetchSheetNames() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(Uri.parse('$apiUrl?action=getSheetNames'));
      final data = jsonDecode(res.body);
      if (data['success'] == true && data['sheets'] != null) {
        final List<String> sheets = List<String>.from(data['sheets']);
        setState(() {
          sheetNames = sheets;
          if (sheets.isNotEmpty) {
            selectedSheet = sheets.first;
          }
        });
        if (selectedSheet.isNotEmpty) {
          loadSheetData(selectedSheet);
        }
      }
    } catch (e) {
      showError('Failed to load tabs: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> loadSheetData(String sheet) async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(
        Uri.parse('$apiUrl?action=getSheetGroupData&sheetName=${Uri.encodeComponent(sheet)}'),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() {
          rawGroups = data['groups'] ?? [];
          applyFilter(_searchController.text);
        });
      }
    } catch (e) {
      showError('Error loading sheet data: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<dynamic> postApi(Map<String, dynamic> body) async {
    try {
      final res = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'text/plain;charset=utf-8'},
        body: jsonEncode(body),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  void handleCellEdit(String sheetName, int rowIndex, int colIndex, String newValue) {
    setState(() => saveStatus = 'Saving R$rowIndex...');

    for (var g in rawGroups) {
      if (g['sheetName'] == sheetName) {
        for (var r in g['rows']) {
          if (r['rowIndex'] == rowIndex) {
            r['values'][colIndex] = newValue;
          }
        }
      }
    }

    postApi({
      'action': 'updateCell',
      'sheetName': sheetName,
      'rowIndex': rowIndex,
      'colIndex': colIndex,
      'newValue': newValue,
    }).then((res) {
      if (mounted) {
        setState(() {
          saveStatus = res['success'] == true ? 'Saved!' : 'Save Failed';
        });
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => saveStatus = '');
        });
      }
    });
  }

  void handleInstantDelete(String sheetName, int rowIndex, String albumTarget) {
    setState(() {
      saveStatus = 'Deleted';
      for (var g in rawGroups) {
        if (g['sheetName'] == sheetName) {
          final List rows = g['rows'];
          final delIdx = rows.indexWhere((r) => r['rowIndex'] == rowIndex);
          if (delIdx != -1) {
            rows.removeAt(delIdx);
            for (int i = delIdx; i < rows.length; i++) {
              rows[i]['rowIndex'] = (rows[i]['rowIndex'] as int) - 1;
            }
          }
        }
      }
      applyFilter(_searchController.text);
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => saveStatus = '');
    });

    postApi({
      'action': 'deleteRow',
      'sheetName': sheetName,
      'rowIndex': rowIndex,
      'albumNameTarget': albumTarget,
    });
  }

  void onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      applyFilter(query);
    });
  }

  void applyFilter(String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) {
      setState(() => filteredGroups = List.from(rawGroups));
      return;
    }

    List<dynamic> filtered = [];
    for (var g in rawGroups) {
      final sName = (g['sheetName'] ?? '').toString().toLowerCase();
      final matchedRows = (g['rows'] as List).where((r) {
        if (sName.contains(q)) return true;
        return (r['values'] as List).any((v) => v.toString().toLowerCase().contains(q));
      }).toList();

      if (matchedRows.isNotEmpty) {
        filtered.add({
          'sheetName': g['sheetName'],
          'headers': g['headers'],
          'rows': matchedRows,
        });
      }
    }

    setState(() => filteredGroups = filtered);
  }

  void showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void openComparisonDrawer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => ComparisonDrawerWidget(sheetNames: sheetNames),
    );
  }

  void openCommonAlbumsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => CommonAlbumsModalWidget(
        onRowDeleted: (sheetName, rowIndex, albumTarget) {
          handleInstantDelete(sheetName, rowIndex, albumTarget);
        },
      ),
    );
  }

  void openTracksDialog(String albumTitle) {
    showDialog(
      context: context,
      builder: (ctx) => TracksDialogWidget(albumTitle: albumTitle, postApi: postApi),
    );
  }

  Color parseHexColor(String? hexString) {
    if (hexString == null || hexString.isEmpty) return Colors.transparent;
    try {
      final hex = hexString.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.transparent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Master Data Manager', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF0F172A),
        actions: [
          if (saveStatus.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: Text(saveStatus, style: const TextStyle(color: Color(0xFF86EFAC), fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            color: Colors.white,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedSheet.isEmpty ? null : selectedSheet,
                            isExpanded: true,
                            items: [
                              ...sheetNames.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13)))),
                              const DropdownMenuItem(value: 'ALL', child: Text('-- All Sheets --', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => selectedSheet = val);
                                loadSheetData(val);
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 5,
                      child: SizedBox(
                        height: 48,
                        child: TextField(
                          controller: _searchController,
                          onChanged: onSearchChanged,
                          decoration: InputDecoration(
                            hintText: '🔍 Search...',
                            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const ColorSide(color: Color(0xFFCBD5E1))),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: openComparisonDrawer,
                        icon: const Icon(Icons.compare_arrows, size: 16),
                        label: const Text('Compare', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: openCommonAlbumsModal,
                        icon: const Icon(Icons.link, size: 16),
                        label: const Text('Common Albums', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredGroups.isEmpty
                    ? const Center(child: Text('No records found.'))
                    : ListView.builder(
                        itemCount: filteredGroups.length,
                        itemBuilder: (ctx, gIdx) {
                          final group = filteredGroups[gIdx];
                          final List headers = group['headers'] ?? [];
                          final List rows = group['rows'] ?? [];
                          final bool isMaster = (group['sheetName'] ?? '').toString().toLowerCase() == 'master sheet';
                          final int nameColIdx = headers.indexWhere((h) => h.toString().toLowerCase() == 'name' || h.toString().toLowerCase() == 'album name');
                          final int statusColIdx = headers.indexWhere((h) => h.toString().toLowerCase().contains('status'));

                          return Container(
                            margin: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  color: const Color(0xFFF1F5F9),
                                  child: Row(
                                    children: [
                                      Text('📄 ${group['sheetName']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(color: const Color(0xFF2563EB), borderRadius: BorderRadius.circular(10)),
                                        child: Text('${rows.length} rows', style: const TextStyle(color: Colors.white, fontSize: 11)),
                                      ),
                                    ],
                                  ),
                                ),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                                    columnSpacing: 16,
                                    columns: [
                                      const DataColumn(label: Text('Row', style: TextStyle(fontWeight: FontWeight.bold))),
                                      const DataColumn(label: Text('Del', style: TextStyle(fontWeight: FontWeight.bold))),
                                      if (isMaster) const DataColumn(label: Text('Tracks', style: TextStyle(fontWeight: FontWeight.bold))),
                                      ...headers.map((h) => DataColumn(label: Text(h.toString(), style: const TextStyle(fontWeight: FontWeight.bold)))),
                                    ],
                                    rows: rows.map((r) {
                                      final int rowNum = r['rowIndex'];
                                      final List vals = r['values'] ?? [];
                                      final List colors = r['colors'] ?? [];
                                      final String albumTitle = nameColIdx != -1 && nameColIdx < vals.length ? vals[nameColIdx] : (vals.isNotEmpty ? vals[0] : '');
                                      final String currentStatus = statusColIdx != -1 && statusColIdx < vals.length ? vals[statusColIdx] : '';

                                      return DataRow(
                                        cells: [
                                          DataCell(Text('$rowNum', style: const TextStyle(color: Color(0xFF64748B)))),
                                          DataCell(
                                            IconButton(
                                              icon: const Text('🗑', style: TextStyle(fontSize: 16)),
                                              onPressed: () => handleInstantDelete(group['sheetName'], rowNum, albumTitle),
                                            ),
                                          ),
                                          if (isMaster)
                                            DataCell(
                                              currentStatus.toLowerCase() == 'selected'
                                                  ? TextButton(
                                                      onPressed: () => openTracksDialog(albumTitle),
                                                      child: const Text('+ Tracks', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                                    )
                                                  : const Text('—', style: TextStyle(color: Color(0xFFCBD5E1))),
                                            ),
                                          ...List.generate(headers.length, (colIdx) {
                                            final val = colIdx < vals.length ? vals[colIdx].toString() : '';
                                            final cellColorHex = colIdx < colors.length ? colors[colIdx].toString() : '';
                                            final cellBg = parseHexColor(cellColorHex);
                                            final isStatus = headers[colIdx].toString().toLowerCase().contains('status');

                                            if (isStatus) {
                                              return DataCell(
                                                Container(
                                                  color: cellBg,
                                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                                  child: DropdownButtonHideUnderline(
                                                    child: DropdownButton<String>(
                                                      value: statusOptions.contains(val) ? val : null,
                                                      hint: Text(val, style: const TextStyle(fontSize: 11)),
                                                      items: statusOptions.map((opt) => DropdownMenuItem(value: opt, child: Text(opt, style: const TextStyle(fontSize: 11)))).toList(),
                                                      onChanged: (newVal) {
                                                        if (newVal != null) {
                                                          handleCellEdit(group['sheetName'], rowNum, colIdx, newVal);
                                                        }
                                                      },
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }

                                            return DataCell(
                                              Container(
                                                color: cellBg,
                                                width: 130,
                                                child: TextFormField(
                                                  initialValue: val,
                                                  style: const TextStyle(fontSize: 12),
                                                  decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                                                  onFieldSubmitted: (newVal) {
                                                    handleCellEdit(group['sheetName'], rowNum, colIdx, newVal);
                                                  },
                                                ),
                                              ),
                                            );
                                          }),
                                        ],
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class CommonAlbumsModalWidget extends StatefulWidget {
  final Function(String sheetName, int rowIndex, String albumTarget) onRowDeleted;
  const CommonAlbumsModalWidget({super.key, required this.onRowDeleted});

  @override
  State<CommonAlbumsModalWidget> createState() => _CommonAlbumsModalWidgetState();
}

class _CommonAlbumsModalWidgetState extends State<CommonAlbumsModalWidget> {
  List<dynamic> commonList = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadCommonAlbums();
  }

  Future<void> loadCommonAlbums() async {
    try {
      final res = await http.get(Uri.parse('$apiUrl?action=getCommonAlbumValues'));
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() => commonList = data['commonAlbums'] ?? []);
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('🔗 Common Albums (${commonList.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const Divider(),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: commonList.length,
                    itemBuilder: (ctx, pIdx) {
                      final item = commonList[pIdx];
                      final List details = item['details'] ?? [];

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(8),
                              color: const Color(0xFFF1F5F9),
                              child: Text('▼ ${item['name']} (${item['totalOccurrences']} records)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                            ...details.asMap().entries.map((entry) {
                              final sIdx = entry.key;
                              final oc = entry.value;
                              return ListTile(
                                dense: true,
                                title: Text('${oc['sheetName']} (R${oc['rowIndex']})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                trailing: IconButton(
                                  icon: const Text('🗑', style: TextStyle(fontSize: 16)),
                                  onPressed: () {
                                    setState(() {
                                      details.removeAt(sIdx);
                                      if (details.isEmpty) commonList.removeAt(pIdx);
                                    });
                                    widget.onRowDeleted(oc['sheetName'], oc['rowIndex'], item['name']);
                                  },
                                ),
                              );
                            }),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class ComparisonDrawerWidget extends StatelessWidget {
  final List<String> sheetNames;
  const ComparisonDrawerWidget({super.key, required this.sheetNames});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 350,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('⧉ Sheet Comparison', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const Divider(),
          const Expanded(child: Center(child: Text('Select comparison sheet from the list.'))),
        ],
      ),
    );
  }
}

class TracksDialogWidget extends StatefulWidget {
  final String albumTitle;
  final Future<dynamic> Function(Map<String, dynamic>) postApi;
  const TracksDialogWidget({super.key, required this.albumTitle, required this.postApi});

  @override
  State<TracksDialogWidget> createState() => _TracksDialogWidgetState();
}

class _TracksDialogWidgetState extends State<TracksDialogWidget> {
  List> tracks = [
    {'song': '', 'folder': ''},
    {'song': '', 'folder': ''}
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Tracks: ${widget.albumTitle}', style: const TextStyle(fontSize: 15)),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: tracks.length,
          itemBuilder: (ctx, i) => Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(hintText: 'Song Title'),
                  onChanged: (v) => tracks[i]['song'] = v,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(hintText: 'Folder'),
                  onChanged: (v) => tracks[i]['folder'] = v,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            widget.postApi({
              'action': 'saveTracksToCollection',
              'albumName': widget.albumTitle,
              'tracks': tracks.where((t) => (t['song'] ?? '').isNotEmpty).toList(),
            });
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
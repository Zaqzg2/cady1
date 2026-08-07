import 'package:flutter/material.dart';

import '../services/manager_service.dart';
import '../utils/formatters.dart';

/// لوحة تحكم المدير: عدد المندوبين، العمليات المستلمة، العمليات غير
/// المستوردة (بانتظار الاعتماد)، وجدول آخر مزامنة لكل مندوب.
class ManagerDashboardScreen extends StatefulWidget {
  const ManagerDashboardScreen({super.key});

  @override
  State<ManagerDashboardScreen> createState() =>
      _ManagerDashboardScreenState();
}

class _ManagerDashboardScreenState extends State<ManagerDashboardScreen> {
  ManagerDashboardStats? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stats = await ManagerService.instance.getDashboardStats();
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    final primary = Theme.of(context).colorScheme.primary;
    final warn = Colors.orange.shade800;
    return Scaffold(
      appBar: AppBar(title: const Text('لوحة التحكم')),
      body: _loading || stats == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _statCard(
                          icon: Icons.groups_outlined,
                          label: 'عدد المندوبين',
                          value: '${stats.repsCount}',
                          color: primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _statCard(
                          icon: Icons.inbox_outlined,
                          label: 'عمليات مستلمة',
                          value: '${stats.receivedOperationsCount}',
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _statCard(
                    icon: Icons.hourglass_top,
                    label: 'عمليات غير مستوردة (بانتظار الاعتماد)',
                    value: '${stats.unimportedOperationsCount}',
                    color: stats.unimportedOperationsCount > 0
                        ? warn
                        : Colors.grey,
                    wide: true,
                  ),
                  const SizedBox(height: 20),
                  const Text('آخر مزامنة لكل مندوب',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  if (stats.repSummaries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                          child: Text('لا يوجد مندوبون بعد',
                              style: TextStyle(color: Colors.black54))),
                    )
                  else
                    Card(
                      child: Column(
                        children: [
                          const Padding(
                            padding:
                                EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            child: Row(
                              children: [
                                Expanded(
                                    flex: 3,
                                    child: Text('المندوب',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold))),
                                Expanded(
                                    flex: 2,
                                    child: Text('آخر مزامنة',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold))),
                                Expanded(
                                    flex: 1,
                                    child: Text('العمليات',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold),
                                        textAlign: TextAlign.center)),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          ...stats.repSummaries.map((s) => Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Row(
                                        children: [
                                          if (!s.representative.isActive)
                                            const Padding(
                                              padding:
                                                  EdgeInsets.only(left: 4),
                                              child: Icon(
                                                  Icons.pause_circle_outline,
                                                  size: 14,
                                                  color: Colors.grey),
                                            ),
                                          Flexible(
                                              child: Text(
                                                  s.representative.repName,
                                                  overflow:
                                                      TextOverflow.ellipsis)),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        s.lastSyncAt != null
                                            ? Formatters.smartWhen(
                                                s.lastSyncAt!)
                                            : '—',
                                        style: const TextStyle(
                                            color: Colors.black54),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Text('${s.lastOperationsCount}',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              )),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool wide = false,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: wide
            ? Row(
                children: [
                  Icon(icon, color: color, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                      child:
                          Text(label, style: const TextStyle(fontSize: 13))),
                  Text(value,
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: color)),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: color, size: 26),
                  const SizedBox(height: 8),
                  Text(value,
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: color)),
                  const SizedBox(height: 2),
                  Text(label,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
      ),
    );
  }
}

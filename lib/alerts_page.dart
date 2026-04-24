import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';
import 'alert_details_page.dart';

class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key});

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  late TabController _tabController;
  RealtimeChannel? channel;

  List<Map<String, dynamic>> allAlerts = [];
  bool _isPopupOpen = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    loadAlerts();
    listenToNewAlerts();
  }

  Future<void> loadAlerts() async {
    final data = await supabase
        .from('alerts')
        .select('*')
        .order('created_at', ascending: false);

    if (!mounted) return;

    setState(() {
      allAlerts = List<Map<String, dynamic>>.from(data);
    });
  }

  void listenToNewAlerts() {
    channel = supabase
        .channel('alerts-stream')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'alerts',
          callback: (payload) async {
            if (!mounted) return;

            if (payload.eventType == PostgresChangeEvent.insert) {
              final newAlert = Map<String, dynamic>.from(payload.newRecord);

              setState(() {
                final exists = allAlerts.any(
                  (alert) => alert['id'].toString() == newAlert['id'].toString(),
                );

                if (!exists) {
                  allAlerts.insert(0, newAlert);
                }
              });

              final category = (newAlert['category'] ?? '').toString();
              final title = getCategoryTitle(category);
              await NotificationService.showInstantAlert(
                title: title,
                body: (newAlert['message'] ?? 'New alert received').toString(),
              );
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: Colors.red.shade700,
                    margin: const EdgeInsets.all(16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    duration: const Duration(seconds: 4),
                    content: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '$title\n${newAlert['message'] ?? 'New alert received'}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );

              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted && !_isPopupOpen) {
                  showAlertPopup(newAlert);
                }
              });
            } else if (payload.eventType == PostgresChangeEvent.update) {
              final updatedAlert = Map<String, dynamic>.from(payload.newRecord);

              setState(() {
                final index = allAlerts.indexWhere(
                  (alert) =>
                      alert['id'].toString() == updatedAlert['id'].toString(),
                );

                if (index != -1) {
                  allAlerts[index] = updatedAlert;
                }
              });
            } else if (payload.eventType == PostgresChangeEvent.delete) {
              final deletedAlert = Map<String, dynamic>.from(payload.oldRecord);

              setState(() {
                allAlerts.removeWhere(
                  (alert) =>
                      alert['id'].toString() == deletedAlert['id'].toString(),
                );
              });
            }
          },
        )
        .subscribe();
  }

  List<Map<String, dynamic>> getAlertsByCategory(String category) {
    return allAlerts
        .where((alert) => (alert['category'] ?? '').toString() == category)
        .toList();
  }

  String? getImageUrl(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) return null;
    return supabase.storage.from('alerts').getPublicUrl(imagePath);
  }

  String formatTime(dynamic createdAt) {
    if (createdAt == null) return 'Time: N/A';

    try {
      final date = DateTime.parse(createdAt.toString()).toLocal();
      return DateFormat('yyyy-MM-dd • hh:mm a').format(date);
    } catch (_) {
      return 'Time: N/A';
    }
  }

  Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'new':
        return Colors.red;
      case 'reviewed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Color getCategoryColor(String category) {
    switch (category) {
      case 'access':
        return Colors.red;
      case 'intrusion':
        return Colors.orange;
      case 'power':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData getCategoryIcon(String category) {
    switch (category) {
      case 'access':
        return Icons.lock_outline;
      case 'intrusion':
        return Icons.sensors;
      case 'power':
        return Icons.bolt;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  String getCategoryTitle(String category) {
    switch (category) {
      case 'access':
        return 'Unauthorized Access Detected';
      case 'intrusion':
        return 'After-Hours Intrusion Detected';
      case 'power':
        return 'Power Monitoring Alert';
      default:
        return 'Security Alert';
    }
  }

  Future<void> markAsReviewed(int id) async {
    await supabase.from('alerts').update({'status': 'reviewed'}).eq('id', id);

    setState(() {
      final index = allAlerts.indexWhere((alert) => alert['id'] == id);
      if (index != -1) {
        allAlerts[index]['status'] = 'reviewed';
      }
    });
  }

  void showAlertPopup(Map<String, dynamic> alert) {
    if (!mounted) return;

    _isPopupOpen = true;

    final imageUrl = getImageUrl(alert['image_path']?.toString());
    final category = (alert['category'] ?? '').toString();
    final categoryColor = getCategoryColor(category);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: categoryColor.withOpacity(0.12),
              child: Icon(
                getCategoryIcon(category),
                color: categoryColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                getCategoryTitle(category),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (imageUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    imageUrl,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 180,
                      width: double.infinity,
                      color: Colors.grey.shade200,
                      child: const Center(
                        child: Icon(Icons.broken_image, size: 42),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Text(
                alert['message']?.toString() ?? 'New security alert received',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 18, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      alert['location']?.toString() ?? 'Unknown location',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.access_time,
                      size: 18, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      formatTime(alert['created_at']),
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Close'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: categoryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AlertDetailsPage(alert: alert),
                ),
              );
            },
            child: const Text('View Details'),
          ),
        ],
      ),
    ).then((_) {
      _isPopupOpen = false;
    });
  }

  Widget buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: color.withOpacity(0.12),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildAlertCard(Map<String, dynamic> alert) {
    final imagePath = alert['image_path']?.toString();
    final imageUrl = getImageUrl(imagePath);
    final status = (alert['status'] ?? 'new').toString();
    final category = (alert['category'] ?? '').toString();
    final sourceId = (alert['source_id'] ?? 'Unknown source').toString();
    final location = (alert['location'] ?? 'Unknown location').toString();
    final isNew = status.toLowerCase() == 'new';
    final categoryColor = getCategoryColor(category);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AlertDetailsPage(alert: alert),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: isNew
                  ? categoryColor.withOpacity(0.20)
                  : Colors.black.withOpacity(0.06),
              blurRadius: isNew ? 18 : 14,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: isNew
                ? categoryColor.withOpacity(0.25)
                : Colors.transparent,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 220,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.shade200,
                      child: const Center(
                        child: Icon(Icons.broken_image, size: 50),
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: categoryColor.withOpacity(0.12),
                        child: Icon(
                          getCategoryIcon(category),
                          color: categoryColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          getCategoryTitle(category),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: getStatusColor(status).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            color: getStatusColor(status),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (alert['message'] != null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            alert['message'].toString(),
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.memory_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          sourceId,
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          location,
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          formatTime(alert['created_at']),
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (status.toLowerCase() == 'new')
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: () => markAsReviewed(alert['id']),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Mark as Reviewed'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: categoryColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildTabContent(String category) {
    final alerts = getAlertsByCategory(category);

    if (alerts.isEmpty) {
      return Center(
        child: Text(
          'No ${category[0].toUpperCase()}${category.substring(1)} alerts yet',
          style: TextStyle(
            fontSize: 17,
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: loadAlerts,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: alerts.length,
        itemBuilder: (context, index) => buildAlertCard(alerts[index]),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    if (channel != null) {
      supabase.removeChannel(channel!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final newCount = allAlerts
        .where((alert) =>
            (alert['status'] ?? '').toString().toLowerCase() == 'new')
        .length;

    final reviewedCount = allAlerts
        .where((alert) =>
            (alert['status'] ?? '').toString().toLowerCase() == 'reviewed')
        .length;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        titleSpacing: 16,
        title: Row(
          children: [
            Image.asset(
              'assets/images/logo.png',
              height: 28,
            ),
            const SizedBox(width: 10),
            const Text(
              'Bank Alerts',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (newCount > 0) ...[
              const SizedBox(width: 10),
              CircleAvatar(
                radius: 12,
                backgroundColor: Colors.red,
                child: Text(
                  '$newCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.red,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.red,
          tabs: const [
            Tab(text: 'Access'),
            Tab(text: 'Intrusion'),
            Tab(text: 'Power'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                buildStatCard(
                  title: 'Total',
                  value: allAlerts.length.toString(),
                  icon: Icons.security,
                  color: Colors.red,
                ),
                const SizedBox(width: 12),
                buildStatCard(
                  title: 'New',
                  value: newCount.toString(),
                  icon: Icons.notification_important_outlined,
                  color: Colors.orange,
                ),
                const SizedBox(width: 12),
                buildStatCard(
                  title: 'Reviewed',
                  value: reviewedCount.toString(),
                  icon: Icons.verified_outlined,
                  color: Colors.green,
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                buildTabContent('access'),
                buildTabContent('intrusion'),
                buildTabContent('power'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AlertDetailsPage extends StatelessWidget {
  final Map<String, dynamic> alert;

  const AlertDetailsPage({super.key, required this.alert});

  String? getImageUrl(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) return null;
    return Supabase.instance.client.storage.from('alerts').getPublicUrl(imagePath);
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

  Widget buildInfoTile({
    required IconData icon,
    required String title,
    required String value,
    Color? iconColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: (iconColor ?? Colors.red).withOpacity(0.12),
            child: Icon(icon, color: iconColor ?? Colors.red, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = getImageUrl(alert['image_path']?.toString());
    final category = (alert['category'] ?? '').toString();
    final status = (alert['status'] ?? 'new').toString();
    final categoryColor = getCategoryColor(category);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: const Text(
          'Alert Details',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (imageUrl != null)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: categoryColor.withOpacity(0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: SizedBox(
                  height: 260,
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
            ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: categoryColor.withOpacity(0.12),
                  child: Icon(
                    getCategoryIcon(category),
                    color: categoryColor,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        getCategoryTitle(category),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        alert['message']?.toString() ?? 'Alert',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
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
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          buildInfoTile(
            icon: Icons.category_outlined,
            title: 'Category',
            value: category.isEmpty ? 'N/A' : category,
            iconColor: categoryColor,
          ),
          buildInfoTile(
            icon: Icons.memory_outlined,
            title: 'Source',
            value: alert['source_id']?.toString() ?? 'N/A',
            iconColor: Colors.deepPurple,
          ),
          buildInfoTile(
            icon: Icons.location_on_outlined,
            title: 'Location',
            value: alert['location']?.toString() ?? 'N/A',
            iconColor: Colors.teal,
          ),
          buildInfoTile(
            icon: Icons.access_time,
            title: 'Time',
            value: formatTime(alert['created_at']),
            iconColor: Colors.indigo,
          ),
          buildInfoTile(
            icon: Icons.flag_outlined,
            title: 'Status',
            value: status,
            iconColor: getStatusColor(status),
          ),
        ],
      ),
    );
  }
}
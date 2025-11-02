import 'package:flutter/material.dart';
import 'image_credits_page.dart'; // 아래 3)에서 만들 파일

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        children: [
          const ListTile(
            title: Text('TAS'),
            subtitle: Text('지도 기반 모의 주행 및 노면 위험 알림 서비스'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('이미지 출처'),
            subtitle: const Text('Flaticon 제공자 크레딧 보기'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ImageCreditsPage()));
            },
          ),
          const Divider(height: 1),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '버전 1.0.0',
              style: TextStyle(color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}

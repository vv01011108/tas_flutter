import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ImageCreditsPage extends StatelessWidget {
  const ImageCreditsPage({super.key});

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);

    // 기본: 외부 브라우저로
    bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);

    // 일부 환경(웹/에뮬레이터)에서 실패 시 플랫폼 기본 모드로 재시도
    if (!ok) {
      ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
    }

    if (!ok) {
      debugPrint('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    const flaticonKR = 'https://www.flaticon.com/kr/free-icons/';
    const judannaAuthor = 'https://www.flaticon.com/authors/judanna';
    const photo3Author = 'https://www.flaticon.com/authors/photo3idea-studio';

    return Scaffold(
      appBar: AppBar(title: const Text('이미지 출처')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '본 앱의 일부 아이콘은 Flaticon에서 제공합니다.',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 12),

          // 제작자별 직접 링크
          
          // 눈 아이콘
          ListTile(
            leading: const Icon(Icons.cloudy_snowing),
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '눈 아이콘 제작자',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                SizedBox(height: 2), // 줄 간격
                Text(
                  '- photo3idea_studio - Flaticon',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            onTap: () => _openUrl(photo3Author),
            trailing: const Icon(Icons.open_in_new),
          ),

          // 비 아이콘
          ListTile(
            leading: const Icon(Icons.beach_access_sharp),
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '비 아이콘 제작자',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                SizedBox(height: 2), // 줄 간격
                Text(
                  '- judanna - Flaticon',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            onTap: () => _openUrl(judannaAuthor),
            trailing: const Icon(Icons.open_in_new),
          ),

          const Divider(),
          // Flaticon 한국어 아이콘 모음(일반 출처 링크)
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Flaticon 아이콘 모음(한국어)'),
            subtitle: const Text('https://www.flaticon.com/kr/free-icons/'),
            onTap: () => _openUrl(flaticonKR),
            trailing: const Icon(Icons.open_in_new),
          ),
        ],
      ),
    );
  }
}

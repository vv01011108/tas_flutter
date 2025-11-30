import 'package:flutter/material.dart';

class HelpersPage extends StatelessWidget {
  const HelpersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('도움 주신 분들')),
      body: ListView(
        children: const [
         ListTile(
            title: Text('허경우 팀장'),
            subtitle: Text('(재)세종테크노파크 | 데이터 수집 지원'),
          ),
          Divider(height: 1),
          ListTile(
            title: Text('김강현 대리'),
            subtitle: Text('(주)서림정보통신 | 데이터 수집 지원'),
          ),
        ],
      ),
    );
  }
}

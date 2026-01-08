import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

void main() {
  runApp(const MaterialApp(home: WolPage()));
}

class WolPage extends StatefulWidget {
  const WolPage({super.key});

  @override
  State<WolPage> createState() => _WolPageState();
}

class _WolPageState extends State<WolPage> {
  // 状态变量
  bool _isLoading = false;
  String _log = '请先点击右上角设置图标\n配置服务器信息';
  
  // 配置项缓存
  String _host = '';
  int _port = 22;
  String _username = '';
  String _password = '';
  String _command = '';

  @override
  void initState() {
    super.initState();
    _loadSettings(); // 启动时加载配置
  }

  // 加载配置
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _host = prefs.getString('host') ?? '';
      _port = prefs.getInt('port') ?? 6022;
      _username = prefs.getString('username') ?? 'root';
      _password = prefs.getString('password') ?? '';
      _command = prefs.getString('command') ?? '/usr/bin/etherwake -b -i br-lan AA:BB:CC:DD:EE:FF';
      
      if (_host.isNotEmpty) {
        _log = '配置已加载，准备就绪';
      }
    });
  }

  // 核心功能：发送 WOL
  Future<void> _sendWol() async {
    if (_host.isEmpty || _password.isEmpty) {
      setState(() => _log = '错误：请先配置 Host 和 密码');
      return;
    }

    setState(() {
      _isLoading = true;
      _log = '正在连接 $_host:$_port...';
    });

    SSHClient? client;
    try {
      final socket = await SSHSocket.connect(_host, _port, timeout: const Duration(seconds: 10));
      
      client = SSHClient(
        socket,
        username: _username,
        onPasswordRequest: () => _password,
      );
      
      _log = '认证中...';
      await client.authenticated;
      
      _log = '发送命令...';
      final session = await client.execute(_command);
      
      final output = await session.stdout.transform(const SystemEncoding().decoder).join();
      final error = await session.stderr.transform(const SystemEncoding().decoder).join();
      
      setState(() {
        _log = '执行完成!\n$output\n$error';
      });
      
    } catch (e) {
      setState(() {
        _log = '连接错误: $e';
      });
    } finally {
      client?.close();
      setState(() => _isLoading = false);
    }
  }

  // 打开设置页面
  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => SettingsPage(
      onSave: _loadSettings, // 保存后重新加载
    )));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('远程唤醒'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              color: Colors.grey[200],
              height: 150,
              child: SingleChildScrollView(child: Text(_log)),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _isLoading ? null : _sendWol,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 20),
                backgroundColor: Colors.blue,
              ),
              child: _isLoading 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('一键唤醒', style: TextStyle(fontSize: 18, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

// 设置页面组件
class SettingsPage extends StatefulWidget {
  final VoidCallback onSave;
  const SettingsPage({super.key, required this.onSave});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _loadToControllers();
  }

  Future<void> _loadToControllers() async {
    final prefs = await SharedPreferences.getInstance();
    _controllers['host'] = TextEditingController(text: prefs.getString('host'));
    _controllers['port'] = TextEditingController(text: (prefs.getInt('port') ?? 6022).toString());
    _controllers['username'] = TextEditingController(text: prefs.getString('username') ?? 'root');
    _controllers['password'] = TextEditingController(text: prefs.getString('password'));
    _controllers['command'] = TextEditingController(text: prefs.getString('command') ?? '/usr/bin/etherwake -b -i br-lan AA:BB:CC:DD:EE:FF');
    setState(() {});
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('host', _controllers['host']!.text);
    await prefs.setInt('port', int.tryParse(_controllers['port']!.text) ?? 6022);
    await prefs.setString('username', _controllers['username']!.text);
    await prefs.setString('password', _controllers['password']!.text);
    await prefs.setString('command', _controllers['command']!.text);
    
    if (mounted) {
      widget.onSave();
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controllers.isEmpty) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text('服务器设置')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(controller: _controllers['host'], decoration: const InputDecoration(labelText: 'VPS IP 地址')),
            TextFormField(controller: _controllers['port'], decoration: const InputDecoration(labelText: '端口 (如 6022)'), keyboardType: TextInputType.number),
            TextFormField(controller: _controllers['username'], decoration: const InputDecoration(labelText: 'SSH 用户名')),
            TextFormField(controller: _controllers['password'], decoration: const InputDecoration(labelText: 'SSH 密码'), obscureText: true),
            TextFormField(controller: _controllers['command'], decoration: const InputDecoration(labelText: '唤醒命令'), maxLines: 2),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _save, child: const Text('保存配置')),
          ],
        ),
      ),
    );
  }
}

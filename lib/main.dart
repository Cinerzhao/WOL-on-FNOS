import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:convert';

void main() {
  runApp(const MaterialApp(
    home: DeviceListPage(),
    debugShowCheckedModeBanner: false,
  ));
}

// ================= 数据模型 =================
class WolDevice {
  String id;
  String name;
  String host;
  int port;
  String username;
  String password;
  String command;

  WolDevice({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.command,
  });

  // 转换为 Map 保存
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'username': username,
    'password': password,
    'command': command,
  };

  // 从 Map 读取
  factory WolDevice.fromJson(Map<String, dynamic> json) => WolDevice(
    id: json['id'] ?? DateTime.now().toString(), // 兼容旧数据
    name: json['name'] ?? '未命名设备',
    host: json['host'] ?? '',
    port: json['port'] ?? 22,
    username: json['username'] ?? 'root',
    password: json['password'] ?? '',
    command: json['command'] ?? '',
  );
}

// ================= 主页面：设备列表 =================
class DeviceListPage extends StatefulWidget {
  const DeviceListPage({super.key});

  @override
  State<DeviceListPage> createState() => _DeviceListPageState();
}

class _DeviceListPageState extends State<DeviceListPage> {
  List<WolDevice> _devices = [];
  // 用来记录正在唤醒的设备ID，显示转圈圈
  final Set<String> _loadingDeviceIds = {};
  // 用来显示每个设备的最后一次执行结果
  final Map<String, String> _deviceStatus = {};

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  // 加载并自动迁移旧数据
  Future<void> _loadDevices() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. 尝试读取新版列表数据
    final String? listJson = prefs.getString('saved_devices_v2');
    
    if (listJson != null) {
      // 如果有新版数据，直接解析
      final List<dynamic> decodeList = jsonDecode(listJson);
      setState(() {
        _devices = decodeList.map((e) => WolDevice.fromJson(e)).toList();
      });
    } else {
      // 2. 如果没有新版数据，检查是否有旧版单机数据 (自动迁移)
      final oldHost = prefs.getString('host');
      if (oldHost != null && oldHost.isNotEmpty) {
        final oldDevice = WolDevice(
          id: DateTime.now().toString(),
          name: '我的 NAS (旧配置)',
          host: oldHost,
          port: prefs.getInt('port') ?? 6022,
          username: prefs.getString('username') ?? 'root',
          password: prefs.getString('password') ?? '',
          command: prefs.getString('command') ?? '/usr/bin/etherwake ...',
        );
        setState(() {
          _devices = [oldDevice];
        });
        _saveDevices(); // 保存为新格式
        
        // 可选：迁移后清除旧key，或者保留以防万一
        // await prefs.remove('host'); 
      }
    }
  }

  Future<void> _saveDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonStr = jsonEncode(_devices.map((e) => e.toJson()).toList());
    await prefs.setString('saved_devices_v2', jsonStr);
  }

  // 执行唤醒逻辑
  Future<void> _wakeDevice(WolDevice device) async {
    setState(() {
      _loadingDeviceIds.add(device.id);
      _deviceStatus[device.id] = '正在连接...';
    });

    SSHClient? client;
    try {
      final socket = await SSHSocket.connect(device.host, device.port, timeout: const Duration(seconds: 10));
      
      client = SSHClient(
        socket,
        username: device.username,
        onPasswordRequest: () => device.password,
      );
      
      await client.authenticated;
      
      final session = await client.execute(device.command);
      
      final output = await utf8.decodeStream(session.stdout.cast<List<int>>());
      final error = await utf8.decodeStream(session.stderr.cast<List<int>>());
      
      setState(() {
        if (error.isNotEmpty) {
          _deviceStatus[device.id] = '失败: $error';
        } else {
          _deviceStatus[device.id] = '指令发送成功!';
        }
      });
      
    } catch (e) {
      setState(() {
        _deviceStatus[device.id] = '错误: $e';
      });
    } finally {
      client?.close();
      setState(() {
        _loadingDeviceIds.remove(device.id);
      });
    }
  }

  void _addOrEditDevice({WolDevice? device}) async {
    final result = await Navigator.push(
      context, 
      MaterialPageRoute(builder: (context) => EditDevicePage(device: device))
    );

    if (result != null) {
      if (result is String && result == 'delete' && device != null) {
        // 删除
        setState(() {
          _devices.removeWhere((d) => d.id == device.id);
        });
      } else if (result is WolDevice) {
        // 保存（新增或修改）
        setState(() {
          final index = _devices.indexWhere((d) => d.id == result.id);
          if (index >= 0) {
            _devices[index] = result;
          } else {
            _devices.add(result);
          }
        });
      }
      _saveDevices();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设备列表'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _addOrEditDevice(),
          ),
        ],
      ),
      body: _devices.isEmpty 
        ? const Center(child: Text('点击右上角 + 添加设备', style: TextStyle(color: Colors.grey)))
        : ListView.builder(
            itemCount: _devices.length,
            padding: const EdgeInsets.all(10),
            itemBuilder: (context, index) {
              final device = _devices[index];
              final isLoading = _loadingDeviceIds.contains(device.id);
              final status = _deviceStatus[device.id];

              return Card(
                elevation: 3,
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: InkWell(
                  onTap: () => _addOrEditDevice(device: device), // 点击卡片编辑
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.router, color: Colors.blue),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(device.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  Text('${device.username}@${device.host}:${device.port}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                ],
                              ),
                            ),
                            // 独立的唤醒按钮
                            isLoading 
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                              : IconButton(
                                  icon: const Icon(Icons.power_settings_new, color: Colors.red, size: 30),
                                  onPressed: () => _wakeDevice(device),
                                ),
                          ],
                        ),
                        if (status != null) ...[
                          const Divider(),
                          Text(status, style: TextStyle(
                            color: status.contains('失败') || status.contains('错误') ? Colors.red : Colors.green,
                            fontSize: 12,
                          )),
                        ]
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
    );
  }
}

// ================= 编辑页面 =================
class EditDevicePage extends StatefulWidget {
  final WolDevice? device;
  const EditDevicePage({super.key, this.device});

  @override
  State<EditDevicePage> createState() => _EditDevicePageState();
}

class _EditDevicePageState extends State<EditDevicePage> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _nameCtrl;
  late TextEditingController _hostCtrl;
  late TextEditingController _portCtrl;
  late TextEditingController _userCtrl;
  late TextEditingController _passCtrl;
  late TextEditingController _cmdCtrl;

  @override
  void initState() {
    super.initState();
    final d = widget.device;
    _nameCtrl = TextEditingController(text: d?.name ?? '');
    _hostCtrl = TextEditingController(text: d?.host ?? '');
    _portCtrl = TextEditingController(text: d?.port.toString() ?? '6022');
    _userCtrl = TextEditingController(text: d?.username ?? 'root');
    _passCtrl = TextEditingController(text: d?.password ?? '');
    _cmdCtrl = TextEditingController(text: d?.command ?? '/usr/bin/etherwake -b -i br-lan AA:BB:CC:DD:EE:FF');
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      final newDevice = WolDevice(
        id: widget.device?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name: _nameCtrl.text.isEmpty ? '未命名设备' : _nameCtrl.text,
        host: _hostCtrl.text,
        port: int.tryParse(_portCtrl.text) ?? 22,
        username: _userCtrl.text,
        password: _passCtrl.text,
        command: _cmdCtrl.text,
      );
      Navigator.pop(context, newDevice);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device == null ? '添加设备' : '编辑设备'),
        actions: [
          if (widget.device != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () {
                // 确认删除
                showDialog(context: context, builder: (ctx) => AlertDialog(
                  title: const Text('确认删除?'),
                  content: const Text('删除后无法恢复。'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                    TextButton(onPressed: () {
                      Navigator.pop(ctx); // 关弹窗
                      Navigator.pop(context, 'delete'); // 关页面并返回删除指令
                    }, child: const Text('删除', style: TextStyle(color: Colors.red))),
                  ],
                ));
              },
            )
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(controller: _nameCtrl, decoration: const InputDecoration(labelText: '设备名称 (如：家里的 NAS)', prefixIcon: Icon(Icons.label))),
            const Divider(),
            TextFormField(controller: _hostCtrl, decoration: const InputDecoration(labelText: '主机地址 (IP / 域名)', prefixIcon: Icon(Icons.dns)), validator: (v) => v!.isEmpty ? '必填' : null),
            TextFormField(controller: _portCtrl, decoration: const InputDecoration(labelText: 'SSH 端口', prefixIcon: Icon(Icons.numbers)), keyboardType: TextInputType.number),
            TextFormField(controller: _userCtrl, decoration: const InputDecoration(labelText: '用户名', prefixIcon: Icon(Icons.person))),
            TextFormField(controller: _passCtrl, decoration: const InputDecoration(labelText: '密码', prefixIcon: Icon(Icons.key)), obscureText: true),
            const Divider(),
            TextFormField(controller: _cmdCtrl, decoration: const InputDecoration(labelText: '唤醒命令', prefixIcon: Icon(Icons.terminal), hintText: 'etherwake ...'), maxLines: 3),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50), backgroundColor: Colors.blue, foregroundColor: Colors.white),
              child: const Text('保存', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}

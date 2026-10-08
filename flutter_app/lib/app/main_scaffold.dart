import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/equalizer/equalizer_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../providers/output_provider.dart';
import '../providers/player_provider.dart';
import '../widgets/mini_player.dart';

class MainScaffold extends ConsumerStatefulWidget {
  const MainScaffold({super.key});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    LibraryScreen(),
    DownloadsScreen(),
    EqualizerScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Initialise the output provider so the Android Bluetooth/DAC listener
    // starts immediately. Listen to output changes and mirror them into the
    // player state so all UI that watches playerProvider.outputStatus updates.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.listenManual(outputProvider, (_, next) {
        ref.read(playerProvider.notifier).updateOutputStatus(next);
      }, fireImmediately: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Current Selected Screen
          IndexedStack(
            index: _currentIndex,
            children: _screens,
          ),

          // Persistent MiniPlayer Floating Above Bottom Bar
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MiniPlayer(),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.library_music_rounded),
            label: 'Library',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.download_rounded),
            label: 'Acquisition',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.tune_rounded),
            label: 'Equalizer',
          ),
        ],
      ),
    );
  }
}

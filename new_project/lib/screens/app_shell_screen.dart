import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_service.dart';

import 'outdoor_map_screen.dart';

class AppShellScreen extends StatefulWidget {
  const AppShellScreen({super.key});

  @override
  State<AppShellScreen> createState() => _AppShellScreenState();
}

class _AppShellScreenState extends State<AppShellScreen> {
  int _selectedIndex = 0;
  OutdoorMapQuickAction _pendingMapAction = OutdoorMapQuickAction.none;

  @override
  void initState() {
    super.initState();
    checkUpdate();
  }

  void checkUpdate() async {
    bool hasUpdate = await UpdateService().checkForUpdate();
    if (hasUpdate && mounted) {
      final version = UpdateService.latestVersion ?? '';
      final notes = UpdateService.latestReleaseNotes ?? 'A new version is available.';

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF1FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    color: Color(0xFF0B5FFF),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Update Available',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (version.isNotEmpty)
                        Text(
                          'v$version',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF0B5FFF),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "What's new:",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: Container(
                    width: double.maxFinite,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: SingleChildScrollView(
                      child: MarkdownBody(
                        data: notes,
                        shrinkWrap: true,
                        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                          p: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF334155)),
                          h1: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, height: 1.5, color: Color(0xFF1E293B)),
                          h2: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, height: 1.5, color: Color(0xFF1E293B)),
                          h3: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, height: 1.5, color: Color(0xFF1E293B)),
                          listBullet: const TextStyle(fontSize: 13, color: Color(0xFF334155)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Later',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
              ),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  final url = Uri.parse('https://naitik2103.github.io/CampusNav/');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0B5FFF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Update Now'),
              ),
            ],
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      _HomeHub(
        onOpenMap: () {
          setState(() {
            _selectedIndex = 1;
          });
        },
        onPlanRoute: () {
          setState(() {
            _selectedIndex = 1;
            _pendingMapAction = OutdoorMapQuickAction.planRoute;
          });
        },
        onPlanMultiStopRoute: () {
          setState(() {
            _selectedIndex = 1;
            _pendingMapAction = OutdoorMapQuickAction.planMultiStopRoute;
          });
        },
      ),
      OutdoorMapScreen(
        initialQuickAction: _pendingMapAction,
        onQuickActionHandled: () {
          if (!mounted || _pendingMapAction == OutdoorMapQuickAction.none) {
            return;
          }
          setState(() {
            _pendingMapAction = OutdoorMapQuickAction.none;
          });
        },
      ),
      const _AccessibilityHub(),
    ];

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: screens),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: const Color(0x1F0B5FFF),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 12,
            );
          }),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map_rounded),
              label: 'Map',
            ),
            NavigationDestination(
              icon: Icon(Icons.accessibility_new_outlined),
              selectedIcon: Icon(Icons.accessibility_new_rounded),
              label: 'Assist',
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeHub extends StatelessWidget {
  final VoidCallback onOpenMap;
  final VoidCallback onPlanRoute;
  final VoidCallback onPlanMultiStopRoute;

  const _HomeHub({
    required this.onOpenMap,
    required this.onPlanRoute,
    required this.onPlanMultiStopRoute,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF0F5FF), Color(0xFFF7FAFF), Color(0xFFFFFFFF)],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CampusNav',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Accessible, voice-first campus guidance',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _showProjectInfoDialog(context),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: Colors.white,
                          border: Border.all(color: const Color(0xFFDCE5F5)),
                        ),
                        child: const Icon(
                          Icons.info_outline_rounded,
                          color: Color(0xFF0B5FFF),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0B5FFF), Color(0xFF1B7CFF)],
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x4D0B5FFF),
                      blurRadius: 24,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Navigate Campus with Confidence',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Real-time map, voice guidance, and accessible route support for everyone.',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: const [
                        _FeatureChip(
                          icon: Icons.route_rounded,
                          text: 'Smart Routing',
                        ),
                        _FeatureChip(
                          icon: Icons.record_voice_over_rounded,
                          text: 'Voice Assist',
                        ),
                        _FeatureChip(
                          icon: Icons.language_rounded,
                          text: 'EN / HI / GU',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: onOpenMap,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: colors.primary,
                      ),
                      icon: const Icon(Icons.navigation_rounded),
                      label: const Text('Start Live Navigation'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Quick Actions',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _QuickCard(
                      icon: Icons.map_rounded,
                      title: 'Open Map',
                      subtitle: 'View live campus map',
                      onTap: onOpenMap,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickCard(
                      icon: Icons.alt_route_rounded,
                      title: 'Plan Route',
                      subtitle: 'Pick From and To places',
                      onTap: onPlanRoute,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _QuickCard(
                icon: Icons.route_rounded,
                title: 'Multi-Stop Route',
                subtitle:
                    'Choose multiple places and get shortest visit order.',
                onTap: onPlanMultiStopRoute,
                fullWidth: true,
              ),
              const SizedBox(height: 12),
              _QuickCard(
                icon: Icons.gps_fixed_rounded,
                title: 'Live Position Accuracy',
                subtitle:
                    'Stabilized GPS tracking with filter and smooth updates for walking.',
                onTap: onOpenMap,
                fullWidth: true,
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: colors.outlineVariant.withOpacity(0.7),
                  ),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How to Start',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    SizedBox(height: 10),
                    _StepRow(
                      number: '1',
                      text: 'Open Map tab or Start Live Navigation',
                    ),
                    _StepRow(
                      number: '2',
                      text: 'Search destination or use route planner',
                    ),
                    _StepRow(
                      number: '3',
                      text: 'Tap Start Navigation for voice guidance',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showProjectInfoDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF1FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.info_rounded,
                          color: Color(0xFF0B5FFF),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CampusNav',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              'A BMP\'26 Project',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Students',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0B5FFF),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStudentPhotoCard(
                          'Patel Harsh',
                          '202301192',
                          'assets/images/harsh.png',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStudentPhotoCard(
                          'Patel Naitik',
                          '202301228',
                          'assets/images/naitik.png',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Professor',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0B5FFF),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildProfessorPhotoCard(
                    'Purbasha Das',
                    'Professor & Mentor',
                    'assets/images/professor.png',
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Note',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0B5FFF),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F6FF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFD0E1FF)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.sticky_note_2_rounded,
                          color: Color(0xFF0B5FFF),
                          size: 20,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'This campus navigation project only works inside the campus of Dhirubhai Ambani University, Gandhinagar, Gujarat, India.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF1E3A8A),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0B5FFF),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Close',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStudentPhotoCard(String name, String rollNo, String imagePath) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x05000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE2E8F0), width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              imagePath,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: const Color(0xFFF8FAFC),
                  child: const Icon(
                    Icons.person_rounded,
                    color: Color(0xFF94A3B8),
                    size: 36,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            rollNo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfessorPhotoCard(String name, String title, String imagePath) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x05000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccessibilityHub extends StatefulWidget {
  const _AccessibilityHub();

  @override
  State<_AccessibilityHub> createState() => _AccessibilityHubState();
}

class _AccessibilityHubState extends State<_AccessibilityHub> {
  final Set<int> _expandedSections = {};
  final ScrollController _scrollController = ScrollController();
  late final List<GlobalKey> _sectionKeys;

  @override
  void initState() {
    super.initState();
    _sectionKeys = List.generate(_sections.length, (_) => GlobalKey());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToSection(int index) {
    final key = _sectionKeys[index];
    final ctx = key.currentContext;
    if (ctx == null) return;
    // A short delay lets the section expand (setState) before we measure.
    Future.delayed(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
        alignment: 0.05, // keep a small gap from the top
      );
    });
  }

  static const List<_GuideSection> _sections = [
    _GuideSection(
      icon: Icons.rocket_launch_rounded,
      title: 'Getting Started',
      color: Color(0xFF0B5FFF),
      items: [
        _GuideItem(
          icon: Icons.home_rounded,
          title: 'Home Screen Overview',
          description:
              'The Home tab is your starting point. It shows quick action cards, a hero banner with CampusNav features, and a "How to Start" guide. Tap any card to jump directly to a feature.',
          tip: 'Use the ℹ️ info button at the top right to view project details — team members and professor.',
        ),
        _GuideItem(
          icon: Icons.navigation_rounded,
          title: 'Start Live Navigation',
          description:
              'Tap "Start Live Navigation" on the home screen banner to open the Map tab directly. The app will request location permission and begin tracking your position automatically.',
          tip: 'Grant "While in Use" location permission for the best experience.',
          steps: [
            'Open CampusNav → Home tab',
            'Tap "Start Live Navigation" button',
            'Allow location access when prompted',
            'Your blue dot will appear on the campus map',
          ],
        ),
        _GuideItem(
          icon: Icons.gps_fixed_rounded,
          title: 'Location & GPS Accuracy',
          description:
              'CampusNav uses advanced GPS smoothing to prevent location jumps. The accuracy badge (bottom-right of map) shows your GPS quality: High (green, ≤8m), Medium (orange, ≤20m), or Low (red).',
          tip: 'Move outdoors away from large buildings for the best GPS signal.',
        ),
      ],
    ),
    _GuideSection(
      icon: Icons.map_rounded,
      title: 'Campus Map',
      color: Color(0xFF7C3AED),
      items: [
        _GuideItem(
          icon: Icons.layers_outlined,
          title: 'Map Layers',
          description:
              'Toggle which elements appear on the map using the Layers button (⊞) in the top-right of the Map tab. You can show/hide campus paths and place markers independently.',
          tip: 'Hide paths to get a cleaner view of places when exploring the campus.',
          steps: [
            'Open Map tab',
            'Tap the layers icon (top-right)',
            'Toggle "Paths" to show/hide road network',
            'Toggle "Places" to show/hide building markers',
          ],
        ),
        _GuideItem(
          icon: Icons.place_rounded,
          title: 'Place Markers & Icons',
          description:
              'Every campus location is shown with a color-coded icon: 🏢 Buildings (purple), 🍽️ Canteen/Restaurant (orange), ☕ Cafes (amber), 🏥 Clinic (red), 📚 Library (cyan), 💻 Lab (indigo), 🎵 Music Room (pink), 🎭 Theatre (deep purple), 🅿️ Parking (blue), and more.',
          tip: 'Tap any marker on the map to see the place name, description, and navigation options.',
        ),
        _GuideItem(
          icon: Icons.route_rounded,
          title: 'Path Difficulty Legend',
          description:
              'Campus paths are color-coded by difficulty. The legend is shown at the bottom-left of the map: Blue = Easy, Orange = Medium, Red = Hard. Dotted lines indicate non-walkable sections.',
          tip: 'Choose easy paths when navigating with heavy bags or limited mobility.',
        ),
        _GuideItem(
          icon: Icons.my_location_rounded,
          title: 'Center on Your Location',
          description:
              'Tap the blue floating button (bottom-right) on the Map tab to center the map on your current position. If location is not yet obtained, it will request it first.',
          steps: [
            'Open Map tab',
            'Tap the floating location button (bottom-right)',
            'Map centers to your current GPS position',
          ],
        ),
      ],
    ),
    _GuideSection(
      icon: Icons.search_rounded,
      title: 'Search',
      color: Color(0xFF059669),
      items: [
        _GuideItem(
          icon: Icons.search_rounded,
          title: 'Search for Any Campus Location',
          description:
              'Use the search bar at the top of the Map tab to find buildings, gates, parking areas, canteen, labs, faculty rooms, and more. Results appear in a dropdown with place type labels.',
          tip: 'Search also supports place aliases — try "F wing", "CS lab", or any short name.',
          steps: [
            'Open Map tab',
            'Tap the search bar at the top',
            'Type a building name, gate, or place type',
            'Tap any result to see its info or get directions',
          ],
        ),
        _GuideItem(
          icon: Icons.person_search_rounded,
          title: 'Search for Faculty',
          description:
              'Type a professor or faculty member\'s name in the search bar. If they are in the faculty directory, their name, department, and room will appear. Tap to get outdoor + indoor directions.',
          tip: 'Faculty results show their block location (e.g., "FB1 · Room 201").',
        ),
        _GuideItem(
          icon: Icons.meeting_room_rounded,
          title: 'Search for Indoor Rooms',
          description:
              'Search for specific rooms (e.g., "201", "CS lab", "principal office") to find indoor locations. Room results show the building and floor number. Tapping them opens the indoor map.',
          tip: 'Room search works for all buildings that have indoor maps configured.',
        ),
        _GuideItem(
          icon: Icons.wc_rounded,
          title: 'Find Nearest Washroom',
          description:
              'Type "washroom near me", "toilet nearby", or "nearest restroom" to instantly find the closest washroom using campus path distances. A route will be displayed automatically.',
          tip: 'Add "men", "women", "male", or "female" to filter by type — e.g. "women washroom near me".',
          steps: [
            'Open Map tab search bar',
            'Type "washroom near me" or "nearest toilet"',
            'The nearest washroom appears with distance info',
            'A route is drawn from your location automatically',
          ],
        ),
      ],
    ),
    _GuideSection(
      icon: Icons.alt_route_rounded,
      title: 'Route Planning',
      color: Color(0xFFDC2626),
      items: [
        _GuideItem(
          icon: Icons.alt_route_rounded,
          title: 'Plan a Route (From → To)',
          description:
              'Use the Route Planner to set a starting point and destination. You can also use your live GPS location as the starting point. The app calculates the best campus-path-based route.',
          tip: 'You can access the route planner from both the Home tab ("Plan Route") and the Map tab (top-right icon).',
          steps: [
            'Tap "Plan Route" on Home tab or the route icon on Map tab',
            'Select "From" — your location or a campus place',
            'Select "To" — type and choose a destination',
            'Tap "Get Route" to calculate the path',
          ],
        ),
        _GuideItem(
          icon: Icons.route_rounded,
          title: 'Multi-Stop Route Planner',
          description:
              'Plan a route through multiple campus locations in one trip. The app automatically optimizes the visit order to minimize total walking distance (TSP optimization).',
          tip: 'Add up to many stops — ideal for visiting multiple departments, labs, and offices in one go.',
          steps: [
            'Tap "Multi-Stop Route" on Home tab or the route icon (top-left) on Map tab',
            'Add multiple destination stops',
            'Toggle "Optimize order" to auto-sort by shortest path',
            'Tap "Start Route" to begin navigation',
          ],
        ),
        _GuideItem(
          icon: Icons.compare_arrows_rounded,
          title: 'Route Comparison Screen',
          description:
              'Before starting navigation, the Route Comparison screen shows you available route options with distance, estimated time, number of steps, and a quality rating. Select the best route and tap "Start Navigation".',
          tip: 'The accessibility chip shows walkability, vehicle access, and wheelchair accessibility for each route.',
        ),
        _GuideItem(
          icon: Icons.directions_rounded,
          title: 'Get Directions to a Place',
          description:
              'From search results, tap the directions arrow (→) next to any place. If your GPS is active, it routes directly from your location. Otherwise, the route planner opens with the destination pre-filled.',
          tip: 'Tapping a place marker on the map shows a popup with a "Navigate" button for quick access.',
        ),
      ],
    ),
    _GuideSection(
      icon: Icons.record_voice_over_rounded,
      title: 'Voice Guidance',
      color: Color(0xFFD97706),
      items: [
        _GuideItem(
          icon: Icons.volume_up_rounded,
          title: 'Turn-by-Turn Voice Instructions',
          description:
              'While navigating, the app speaks turn-by-turn instructions automatically. It gives early warnings before turns and immediate instructions as you approach each turn point.',
          tip: 'Voice guidance adjusts based on your walking speed and distance to the next turn.',
        ),
        _GuideItem(
          icon: Icons.translate_rounded,
          title: 'Language Selection (EN / HI / GU)',
          description:
              'During navigation, tap the language buttons at the top of the screen to switch between English, Hindi (हिंदी), and Gujarati (ગુજરાતી). Navigation instructions are fully localized in all three languages.',
          tip: 'The app confirms the language switch with a spoken message in the new language.',
          steps: [
            'Start navigation to any destination',
            'Look for EN / HI / GU buttons at the top of navigation screen',
            'Tap your preferred language',
            'Voice guidance will immediately switch languages',
          ],
        ),
        _GuideItem(
          icon: Icons.replay_rounded,
          title: 'Repeat Current Instruction',
          description:
              'Missed a voice instruction? Tap the replay button on the navigation screen to hear the current step again in your chosen language.',
          tip: 'This is especially useful in noisy outdoor environments.',
        ),
        _GuideItem(
          icon: Icons.volume_off_rounded,
          title: 'Mute / Unmute Voice',
          description:
              'Tap the speaker icon on the navigation screen to toggle voice guidance on or off at any time without stopping navigation.',
          tip: 'Map-based step display continues even when voice is muted.',
        ),
      ],
    ),
    _GuideSection(
      icon: Icons.apartment_rounded,
      title: 'Indoor Navigation',
      color: Color(0xFF0891B2),
      items: [
        _GuideItem(
          icon: Icons.map_outlined,
          title: 'Automatic Indoor Detection',
          description:
              'When you physically walk inside a building that has an indoor map configured, CampusNav automatically detects this and offers to open the indoor floor plan for that building.',
          tip: 'This uses GPS geofencing — stay near a building entrance for the most accurate detection.',
        ),
        _GuideItem(
          icon: Icons.meeting_room_outlined,
          title: 'Browse Indoor Floor Plans',
          description:
              'The indoor map shows the building boundary, rooms (blue dots), staircase transition points (orange squares), and navigation paths (blue lines). Tap a room to highlight it and see route guidance.',
          tip: 'Rooms are labeled by name and category. Tap any room in the list below the floor plan to select it.',
          steps: [
            'Enter a building or search for a room/faculty',
            'The Indoor Map screen opens automatically',
            'Use the floor dropdown to switch between floors',
            'Tap a room to see its route from your entry point',
          ],
        ),
        _GuideItem(
          icon: Icons.stairs_rounded,
          title: 'Multi-Floor Navigation',
          description:
              'When your target room is on a different floor, the indoor map shows a transition hint (e.g., "Switch from Floor 1 to Floor 2 via Staircase A"). The map updates to the destination floor.',
          tip: 'Orange squares on the floor plan mark staircases.',
        ),
        _GuideItem(
          icon: Icons.person_pin_circle_rounded,
          title: 'Faculty Room Navigation',
          description:
              'Searching for a faculty member automatically finds their building, block, and room. The app routes you outdoors to the building entrance and then opens the indoor map for the specific room.',
          tip: 'Faculty data includes department and block mapping for precise indoor routing.',
        ),
      ],
    ),
    _GuideSection(
      icon: Icons.accessibility_new_rounded,
      title: 'Accessibility Features',
      color: Color(0xFF7C3AED),
      items: [
        _GuideItem(
          icon: Icons.accessible_rounded,
          title: 'Wheelchair Accessibility Info',
          description:
              'The Route Comparison screen shows wheelchair accessibility status for each route. Routes using campus paths that are not wheelchair-friendly are clearly marked.',
          tip: 'Look for the green accessibility chip to confirm a route is wheelchair-friendly.',
        ),
        _GuideItem(
          icon: Icons.gps_fixed_rounded,
          title: 'Stable GPS Tracking',
          description:
              'CampusNav uses position smoothing (35% interpolation factor) and quality filtering to prevent erratic location jumps. It ignores GPS fixes older than 15 seconds or with accuracy worse than 45 meters.',
          tip: 'The GPS accuracy badge on the map shows your current fix quality in real time.',
        ),
        _GuideItem(
          icon: Icons.directions_walk_rounded,
          title: 'Walking Speed Filter',
          description:
              'The app filters out impossible location jumps (over 8 m/s) to prevent phantom routing. This ensures navigation remains accurate even in areas with weak GPS signal.',
          tip: 'Stay on campus paths for the most accurate route tracking.',
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F5FF),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            expandedHeight: 160,
            floating: false,
            pinned: true,
            backgroundColor: const Color(0xFF0B5FFF),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0B5FFF), Color(0xFF1B7CFF)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.auto_stories_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'User Guide',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Text(
                          'Everything you need to navigate campus',
                          style: TextStyle(
                            color: Color(0xCCFFFFFF),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _sections.asMap().entries.map((entry) {
                  final i = entry.key;
                  final s = entry.value;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        // Radio/accordion behavior: toggle if already open,
                        // otherwise close all and open only this one.
                        if (_expandedSections.contains(i)) {
                          _expandedSections.remove(i);
                        } else {
                          _expandedSections.clear();
                          _expandedSections.add(i);
                          _scrollToSection(i);
                        }
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: _expandedSections.contains(i)
                            ? s.color
                            : Colors.white,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: _expandedSections.contains(i)
                              ? s.color
                              : const Color(0xFFDCE5F5),
                        ),
                        boxShadow: [
                          if (_expandedSections.contains(i))
                            BoxShadow(
                              color: s.color.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            s.icon,
                            size: 14,
                            color: _expandedSections.contains(i)
                                ? Colors.white
                                : s.color,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            s.title,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _expandedSections.contains(i)
                                  ? Colors.white
                                  : s.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          // ── Map Icon Legend ────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _MapIconLegendCard(),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: _sections.asMap().entries.map((entry) {
                final index = entry.key;
                final section = entry.value;
                final isExpanded = _expandedSections.contains(index);

                return Padding(
                  key: _sectionKeys[index],
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: _GuideSectionCard(
                    section: section,
                    isExpanded: isExpanded,
                    onToggle: () => setState(() {
                      if (isExpanded) {
                        _expandedSections.remove(index);
                      } else {
                        _expandedSections.add(index);
                        _scrollToSection(index);
                      }
                    }),
                  ),
                );
              }).toList(),
            ),
          ),
          // ── Pro Tips ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0B5FFF), Color(0xFF1B7CFF)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.lightbulb_rounded,
                          color: Colors.amber,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Pro Tips',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    _ProTipRow(
                      text:
                          'In case of not loading map check your internet connection.',
                    ),
                    _ProTipRow(
                      text:
                          'Try zoom in/out to load the map.',
                    ),
                    _ProTipRow(
                      text:
                          'Search "washroom near me" for instant nearby restroom routing.',
                    ),
                    _ProTipRow(
                      text:
                          'Use Multi-Stop Route for visiting multiple departments in one trip.',
                    ),
                    _ProTipRow(
                      text:
                          'Switch to Hindi or Gujarati voice during navigation for local guidance.',
                    ),
                    _ProTipRow(
                      text:
                          'Tap any map marker to view place details before navigating.',
                    ),
                    _ProTipRow(
                      text:
                          'Indoor maps auto-open when you physically enter a mapped building.',
                    ),
                    _ProTipRow(
                      text:
                          'If the way is closed or modified try too look on the normal map and then trace the path manually.',
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ── Disclaimer ───────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFEE2E2)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFEF4444),
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Disclaimer',
                          style: TextStyle(
                            color: Color(0xFF991B1B),
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    _DisclaimerBulletRow(
                      text: 'This campus navigation application developed by students of Dhirubhai Ambani University, Gandhinagar with the help of professor.',
                    ),
                    _DisclaimerBulletRow(
                      text: 'Application may take 10 - 15 seconds to load the map.',
                    ),
                    _DisclaimerBulletRow(
                      text: 'Application may take 20 - 25 seconds to get accurate live position.',
                    ),
                    _DisclaimerBulletRow(
                      text: 'Zoom in for finding washrooms and stairs if it is available.',
                    ),
                    _DisclaimerBulletRow(
                      text: 'Stairs are only added where we thought it is needed.',
                    ),
                    _DisclaimerBulletRow(
                      text: 'Traced path may be little bit inaccurate sometimes which is very rare case.So, keep your eyes open for the best results.',
                    ),
                    _DisclaimerBulletRow(
                      text: 'Application hallucinates your live position when moving way too fast.',
                    ),
                    _DisclaimerBulletRow(
                      text: 'Indoor navigation is only available for CEP and LAB buildings.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// Map Icon Legend Card
// ────────────────────────────────────────────────────────────
class _MapIconLegendCard extends StatelessWidget {
  const _MapIconLegendCard();

  static const _outdoor = <_LegendEntry>[
    // Exact icons from _getPlaceIcon() / colors from _getPlaceColor()
    _LegendEntry(Icons.apartment,       Colors.purple,          'Building'),
    _LegendEntry(Icons.computer,        Colors.indigoAccent,    'Lab / Laboratory'),
    _LegendEntry(Icons.restaurant,      Colors.deepOrange,      'Canteen / Restaurant'),
    _LegendEntry(Icons.coffee,          Colors.orangeAccent,    'Café / Coffee Shop'),
    _LegendEntry(Icons.local_hospital,  Colors.redAccent,       'Clinic / Hospital'),
    _LegendEntry(Icons.menu_book,       Colors.cyan,            'Library'),
    _LegendEntry(Icons.local_parking,   Colors.blue,            'Parking'),
    _LegendEntry(Icons.wc,              Colors.green,           'Washroom / Restroom'),
    _LegendEntry(Icons.stairs,          Colors.amber,           'Stairs'),
    _LegendEntry(Icons.sports_soccer,   Colors.lightGreen,      'Playground / Sports'),
    _LegendEntry(Icons.fitness_center,  Colors.blueGrey,        'Gym'),
    _LegendEntry(Icons.music_note,      Colors.pink,            'Music Room'),
    _LegendEntry(Icons.theaters,        Colors.deepPurpleAccent,'Theatre / Auditorium'),
    _LegendEntry(Icons.business,        Colors.indigo,          'Office / Admin'),
    _LegendEntry(Icons.account_balance, Colors.teal,            'Bank / ATM'),
    _LegendEntry(Icons.meeting_room,    Colors.brown,           'Gate / Entry'),
    _LegendEntry(Icons.cake,            Colors.pinkAccent,      'Bakery'),
    _LegendEntry(Icons.inventory,       Colors.blueGrey,        'Store Room'),
    _LegendEntry(Icons.store,           Color(0xFF00529B),      'Amul'),
    _LegendEntry(Icons.place,           Colors.amber,           'Landmark'),
    _LegendEntry(Icons.location_on,     Colors.grey,            'Other Place'),
  ];

  static const _indoor = <_LegendEntry>[
    // Exact from indoor_navigation_screen.dart _buildLegend / CustomPainter
    _LegendEntry(Icons.circle,             Color(0xFFEF4444), 'Room Door'),
    _LegendEntry(Icons.crop_square_rounded,Color(0xFF2563EB), 'Stairs Transition'),
    _LegendEntry(Icons.circle,             Color(0xFF10B981), 'You Are Here (Entry)'),
  ];

  static const _paths = <_LegendEntry>[
    _LegendEntry(Icons.remove_rounded,   Colors.blue,       'Easy path'),
    _LegendEntry(Icons.remove_rounded,   Colors.orange,     'Medium path'),
    _LegendEntry(Icons.remove_rounded,   Colors.red,        'Hard path'),
  ];


  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8EEF8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0B5FFF), Color(0xFF2979FF)],
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.legend_toggle_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Map Icon Legend',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'All map symbols explained',
                      style: TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Outdoor Place Icons
          _LegendGroup(
            title: 'Outdoor Place Markers',
            icon: Icons.place_rounded,
            color: const Color(0xFF7C3AED),
            entries: _outdoor,
          ),

          const Divider(height: 1, color: Color(0xFFF1F5F9), indent: 16, endIndent: 16),

          // Indoor Map Icons
          _LegendGroup(
            title: 'Indoor Map Symbols',
            icon: Icons.apartment_rounded,
            color: const Color(0xFF0891B2),
            entries: _indoor,
          ),

          const Divider(height: 1, color: Color(0xFFF1F5F9), indent: 16, endIndent: 16),

          // Path Colours
          _LegendGroup(
            title: 'Path Difficulty Colours',
            icon: Icons.route_rounded,
            color: const Color(0xFF059669),
            entries: _paths,
            isPathGroup: true,
          ),

          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _LegendEntry {
  final IconData icon;
  final Color color;
  final String label;
  const _LegendEntry(this.icon, this.color, this.label);
}

class _LegendGroup extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<_LegendEntry> entries;
  final bool isPathGroup;

  const _LegendGroup({
    required this.title,
    required this.icon,
    required this.color,
    required this.entries,
    this.isPathGroup = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sub-header
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Grid: 2 columns
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 3.6,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final e = entries[i];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: e.color.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: e.color.withOpacity(0.18)),
                ),
                child: Row(
                  children: [
                    isPathGroup
                        ? Container(
                            width: 24,
                            height: 4,
                            decoration: BoxDecoration(
                              color: e.color,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          )
                        : Icon(e.icon, size: 18, color: e.color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.label,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ProTipRow extends StatelessWidget {
  final String text;
  const _ProTipRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '→',
            style: TextStyle(
              color: Colors.amber,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xDDFFFFFF),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DisclaimerBulletRow extends StatelessWidget {
  final String text;
  const _DisclaimerBulletRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '•',
            style: TextStyle(
              color: Color(0xFFEF4444),
              fontWeight: FontWeight.w900,
              fontSize: 14,
              height: 1.1,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF7F1D1D),
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideSectionCard extends StatelessWidget {
  final _GuideSection section;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _GuideSectionCard({
    required this.section,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
              isExpanded ? section.color.withOpacity(0.3) : const Color(0xFFE8EEF8),
        ),
        boxShadow: [
          BoxShadow(
            color: isExpanded
                ? section.color.withOpacity(0.08)
                : const Color(0x0A000000),
            blurRadius: isExpanded ? 16 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: section.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(section.icon, color: section.color, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          section.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          '${section.items.length} topic${section.items.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: section.color.withOpacity(0.8),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: section.color,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            Divider(
              height: 1,
              color: section.color.withOpacity(0.15),
              indent: 16,
              endIndent: 16,
            ),
            ...section.items.asMap().entries.map((entry) {
              final i = entry.key;
              final item = entry.value;
              return _GuideItemTile(
                item: item,
                accentColor: section.color,
                isLast: i == section.items.length - 1,
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _GuideItemTile extends StatefulWidget {
  final _GuideItem item;
  final Color accentColor;
  final bool isLast;

  const _GuideItemTile({
    required this.item,
    required this.accentColor,
    required this.isLast,
  });

  @override
  State<_GuideItemTile> createState() => _GuideItemTileState();
}

class _GuideItemTileState extends State<_GuideItemTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: widget.accentColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        widget.item.icon,
                        color: widget.accentColor,
                        size: 17,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.item.title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.item.description,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF475569),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (widget.item.steps != null || widget.item.tip != null)
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: widget.accentColor.withOpacity(0.6),
                          size: 20,
                        ),
                      ),
                  ],
                ),
                if (_expanded) ...[
                  const SizedBox(height: 12),
                  if (widget.item.steps != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFDCE5F5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Steps',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: widget.accentColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...widget.item.steps!.asMap().entries.map((entry) {
                            final stepNum = entry.key + 1;
                            final stepText = entry.value;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 20,
                                    height: 20,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: widget.accentColor,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      '$stepNum',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      stepText,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF334155),
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                    if (widget.item.tip != null) const SizedBox(height: 8),
                  ],
                  if (widget.item.tip != null)
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFEF3C7)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '💡',
                            style: TextStyle(fontSize: 14),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.item.tip!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF92400E),
                                fontWeight: FontWeight.w500,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        if (!widget.isLast)
          Divider(
            height: 1,
            color: widget.accentColor.withOpacity(0.1),
            indent: 16,
            endIndent: 16,
          ),
      ],
    );
  }
}

class _GuideSection {
  final IconData icon;
  final String title;
  final Color color;
  final List<_GuideItem> items;

  const _GuideSection({
    required this.icon,
    required this.title,
    required this.color,
    required this.items,
  });
}

class _GuideItem {
  final IconData icon;
  final String title;
  final String description;
  final String? tip;
  final List<String>? steps;

  const _GuideItem({
    required this.icon,
    required this.title,
    required this.description,
    this.tip,
    this.steps,
  });
}

class _QuickCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool fullWidth;

  const _QuickCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.outlineVariant.withOpacity(0.7)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF1FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: colors.primary),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
              maxLines: fullWidth ? null : 2,
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FeatureChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x26FFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x4DFFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}



class _StepRow extends StatelessWidget {
  final String number;
  final String text;

  const _StepRow({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFF0B5FFF),
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(text, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}


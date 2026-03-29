import 'package:go_router/go_router.dart';
// import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/about_screen.dart';
import 'screens/browser_screen.dart';
import 'screens/chat_hub_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/torrents_screen.dart';
import 'widgets/platform_adaptive_scaffold.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const HomeScreen(),
        ),
        GoRoute(
          path: '/about',
          builder: (_, __) => const AboutScreen(),
        ),
        GoRoute(
          path: '/browser',
          builder: (_, __) => const BrowserScreen(),
        ),
        GoRoute(
          path: '/chat_hub',
          builder: (_, __) => const ChatHubScreen(),
        ),
        GoRoute(
          path: '/messages',
          builder: (_, __) => const MessagesScreen(),
        ),
        GoRoute(
          path: '/torrents',
          builder: (_, __) => const TorrentsScreen(),
        ),
      ],
    ),
  ],
);

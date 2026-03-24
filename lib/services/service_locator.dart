import 'package:get_it/get_it.dart';
import 'package:vault_the_spire/services/identity_service.dart';
import 'package:vault_the_spire/services/settings_service.dart';
import 'package:vault_the_spire/services/theme_service.dart';
import 'package:vault_the_spire/services/startup_service.dart';
import 'package:vault_the_spire/services/tray_service.dart';

final GetIt sl = GetIt.instance;

Future<void> setupServiceLocator() async {
  sl.registerLazySingleton<IdentityService>(() => IdentityService.instance);
  sl.registerLazySingleton<SettingsService>(() => SettingsService.instance);
  sl.registerLazySingleton<ThemeService>(() => ThemeService.instance);
  sl.registerLazySingleton<StartupService>(() => StartupService());
  sl.registerLazySingleton<TrayService>(() => TrayService(
        shouldMinimiseToTray: () => SettingsService.instance.minimizeToTrayOnClose,
        onTrayShow: () async {
          await Future.value();
        },
        onTrayQuit: () async {
          await Future.value();
        },
      ));
}

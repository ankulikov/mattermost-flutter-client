abstract final class AuthStrings {
  static const String title = 'Подключение к Mattermost';
  static const String description =
      'Укажите адрес сервера и персональный токен. Получить токен можно в '
      'Mattermost: Профиль → Безопасность → Персональные токены доступа.';
  static const String serverLabel = 'Адрес сервера';
  static const String serverHint = 'https://mattermost.example.com';
  static const String tokenLabel = 'Персональный токен';
  static const String showToken = 'Показать токен';
  static const String hideToken = 'Скрыть токен';
  static const String connect = 'Подключиться';
  static const String cancel = 'Отмена';
  static const String signOut = 'Выйти';
  static const String connected = 'Подключено';
  static const String invalidCredentials = 'Токен недействителен или отозван.';
  static const String networkError =
      'Не удалось связаться с сервером. Проверьте адрес и подключение.';
  static const String invalidInput =
      'Укажите корректный HTTPS-адрес сервера и непустой токен.';
  static const String storageError = 'Не удалось безопасно сохранить токен.';
}

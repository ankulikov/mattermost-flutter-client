abstract final class AuthStrings {
  static const String title = 'Подключение к Mattermost';
  static const String description =
      'Укажите адрес Mattermost-сервера, чтобы выбрать доступный способ входа.';
  static const String serverLabel = 'Адрес сервера';
  static const String serverHint = 'https://mattermost.example.com';
  static const String continueLabel = 'Продолжить';
  static const String chooseMethod = 'Выберите способ входа';
  static const String loginWithToken = 'Войти по токену';
  static const String tokenTitle = 'Вход по токену';
  static const String tokenDescription =
      'Введите персональный токен доступа Mattermost.';
  static const String tokenLabel = 'Токен доступа';
  static const String tokenHint = 'Вставьте токен';
  static const String signIn = 'Войти';
  static const String back = 'Назад';
  static const String loadingMethods = 'Проверяем сервер и способы входа…';
  static const String openingBrowser = 'Открываем защищённое окно входа…';
  static const String validatingSession = 'Проверяем сессию…';
  static const String cancel = 'Отмена';
  static const String retry = 'Повторить';
  static const String changeServer = 'Другой сервер';
  static const String signOut = 'Выйти';
  static const String connected = 'Подключено';
  static const String invalidCredentials =
      'Сессия недействительна или была отозвана. Войдите снова.';
  static const String networkError =
      'Не удалось связаться с сервером. Проверьте адрес и подключение.';
  static const String invalidInput = 'Укажите корректный HTTPS-адрес сервера.';
  static const String storageError = 'Не удалось безопасно сохранить сессию.';
  static const String ssoUnavailable =
      'На этом сервере не включены поддерживаемые способы единого входа.';
  static const String browserUnavailable =
      'Защищённое окно входа недоступно на этой платформе.';
  static const String ssoFailed =
      'Не удалось завершить единый вход. Попробуйте ещё раз.';
  static const String tokenMissing =
      'Сервер не завершил вход. Попробуйте ещё раз.';
  static const String sessionExpired =
      'Сохранённая сессия истекла. Войдите снова.';
  static const String restoreFailed =
      'Не удалось проверить сохранённую сессию. Повторите попытку позже.';
}

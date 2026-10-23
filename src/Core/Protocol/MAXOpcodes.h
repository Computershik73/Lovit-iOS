//
//  MAXOpcodes.h
//  Max — коды операций протокола.
//
//  Порт lib/core/protocol/opcode_map.dart.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, MAXOpcode) {
    // Сессия
    MAXOpcodePing = 1,
    MAXOpcodeDebug = 2,
    MAXOpcodeReconnect = 3,
    MAXOpcodeLog = 5,
    MAXOpcodeSessionInit = 6,
    MAXOpcodeContactsGet = 8,

    // Профиль
    MAXOpcodeProfile = 16,

    // Авторизация
    MAXOpcodeAuthRequest = 17,
    MAXOpcodeAuth = 18,
    MAXOpcodeLogin = 19,
    MAXOpcodeLogout = 20,
    MAXOpcodeSync = 21,
    MAXOpcodeConfig = 22,
    MAXOpcodeAuthConfirm = 23,

    // Авторизация 2FA
    MAXOpcodeAuthLoginRestorePassword = 101,
    MAXOpcodeAuth2faDetails = 104,
    MAXOpcodeExternalCallback = 105,
    MAXOpcodeAuthValidatePassword = 107,
    MAXOpcodeAuthValidateHint = 108,
    MAXOpcodeAuthVerifyEmail = 109,
    MAXOpcodeAuthCheckEmail = 110,
    MAXOpcodeAuthSet2fa = 111,
    MAXOpcodeAuthCreateTrack = 112,
    MAXOpcodeAuthCheckPassword = 113,
    MAXOpcodeAuthLoginCheckPassword = 115,
    MAXOpcodeAuthLoginProfileDelete = 116,

    // Стикеры
    MAXOpcodePresetAvatars = 25,
    MAXOpcodeAssetsGet = 26,
    MAXOpcodeAssetsUpdate = 27,
    MAXOpcodeAssetsGetByIds = 28,
    MAXOpcodeAssetsAdd = 29,
    MAXOpcodeAssetsRemove = 259,
    MAXOpcodeAssetsMove = 260,
    MAXOpcodeAssetsListModify = 261,

    // Контакты
    MAXOpcodeContactInfo = 32,
    MAXOpcodeContactAdd = 33,
    MAXOpcodeContactUpdate = 34,
    MAXOpcodeContactPresence = 35,
    MAXOpcodeContactList = 36,
    MAXOpcodeContactSearch = 37,
    MAXOpcodeContactMutual = 38,
    MAXOpcodeContactPhotos = 39,
    MAXOpcodeContactSort = 40,
    MAXOpcodeContactAddByPhone = 41,
    MAXOpcodeContactVerify = 42,
    MAXOpcodeRemoveContactPhoto = 43,
    MAXOpcodeContactInfoByPhone = 46,

    // Чаты
    MAXOpcodeChatInfo = 48,
    MAXOpcodeChatHistory = 49,
    MAXOpcodeChatMark = 50,
    MAXOpcodeChatMedia = 51,
    MAXOpcodeChatDelete = 52,
    MAXOpcodeChatsList = 53,
    MAXOpcodeChatClear = 54,
    MAXOpcodeChatUpdate = 55,
    MAXOpcodeChatCheckLink = 56,
    MAXOpcodeChatJoin = 57,
    MAXOpcodeChatLeave = 58,
    MAXOpcodeChatMembers = 59,
    MAXOpcodePublicSearch = 60,
    MAXOpcodeChatPersonalConfig = 61,
    MAXOpcodeChatCreate = 63,

    // Сообщения
    MAXOpcodeMsgSend = 64,
    MAXOpcodeMsgTyping = 65,
    MAXOpcodeMsgDelete = 66,
    MAXOpcodeMsgEdit = 67,
    MAXOpcodeChatSearch = 68,
    MAXOpcodeMsgSharePreview = 70,
    MAXOpcodeMsgGet = 71,
    MAXOpcodeMsgSearchTouch = 72,
    MAXOpcodeMsgSearch = 73,
    MAXOpcodeMsgGetStat = 74,
    MAXOpcodeChatSubscribe = 75,
    MAXOpcodeMsgDeleteRange = 92,

    // Реакции
    MAXOpcodeMsgReaction = 178,
    MAXOpcodeMsgCancelReaction = 179,
    MAXOpcodeMsgGetReactions = 180,
    MAXOpcodeMsgGetDetailedReactions = 181,
    MAXOpcodeChatReactionsSettingsSet = 257,
    MAXOpcodeReactionsSettingsGetByChatId = 258,

    // Звонки
    MAXOpcodeVideoChatStart = 76,
    MAXOpcodeChatMembersUpdate = 77,
    MAXOpcodeVideoChatStartActive = 78,
    MAXOpcodeVideoChatHistory = 79,
    MAXOpcodeVideoChatDeleteHistory = 164,
    MAXOpcodeVideoChatCreateJoinLink = 84,
    MAXOpcodeVideoChatJoinByLink = 166,
    MAXOpcodeVideoChatMembers = 195,
    MAXOpcodeGetInboundCalls = 103,

    // Медиа и файлы
    MAXOpcodePhotoUpload = 80,
    MAXOpcodeStickerUpload = 81,
    MAXOpcodeVideoUpload = 82,
    MAXOpcodeVideoPlay = 83,
    MAXOpcodeChatPinSetVisibility = 86,
    MAXOpcodeFileUpload = 87,
    MAXOpcodeFileDownload = 88,
    MAXOpcodeLinkInfo = 89,
    MAXOpcodeAudioPlay = 301,

    // Комментарии
    MAXOpcodeCommentsInfo = 91,

    // Сессии
    MAXOpcodeSessionsInfo = 96,
    MAXOpcodeSessionsClose = 97,
    MAXOpcodePhoneBindRequest = 98,
    MAXOpcodePhoneBindConfirm = 99,

    // Боты
    MAXOpcodeChatComplain = 117,
    MAXOpcodeMsgSendCallback = 118,
    MAXOpcodeSuspendBot = 119,
    MAXOpcodeChatBotCommands = 144,
    MAXOpcodeBotInfo = 145,

    // Геолокация и упоминания
    MAXOpcodeLocationStop = 124,
    MAXOpcodeGetLastMentions = 127,

    // Создание стикеров
    MAXOpcodeStickerCreate = 193,
    MAXOpcodeStickerSuggest = 194,

    // Пуши от сервера
    MAXOpcodeNotifMessage = 128,
    MAXOpcodeNotifTyping = 129,
    MAXOpcodeNotifMark = 130,
    MAXOpcodeNotifContact = 131,
    MAXOpcodeNotifPresence = 132,
    MAXOpcodeNotifConfig = 134,
    MAXOpcodeNotifChat = 135,
    MAXOpcodeNotifAttach = 136,
    MAXOpcodeNotifCallStart = 137,
    MAXOpcodeNotifContactSort = 139,
    MAXOpcodeNotifMsgDeleteRange = 140,
    MAXOpcodeNotifMsgDelete = 142,
    MAXOpcodeNotifCallbackAnswer = 143,
    MAXOpcodeNotifLocation = 147,
    MAXOpcodeNotifLocationRequest = 148,
    MAXOpcodeNotifAssetsUpdate = 150,
    MAXOpcodeNotifDraft = 152,
    MAXOpcodeNotifDraftDiscard = 153,
    MAXOpcodeNotifMsgDelayed = 154,
    MAXOpcodeNotifMsgReactionsChanged = 155,
    MAXOpcodeNotifMsgYouReacted = 156,
    MAXOpcodeNotifProfile = 159,
    MAXOpcodeNotifBanners = 292,
    MAXOpcodeNotifFolders = 277,

    // Транскрибация
    MAXOpcodeAudioTranscription = 202,
    MAXOpcodeTranscriptionResult = 293,

    // Разное
    MAXOpcodeOkToken = 158,
    MAXOpcodeWebAppInitData = 160,
    MAXOpcodeComplain = 161,
    MAXOpcodeComplainReasonsGet = 162,
    MAXOpcodeDraftSave = 176,
    MAXOpcodeDraftDiscard = 177,
    MAXOpcodeChatHide = 196,
    MAXOpcodeChatSearchCommonParticipants = 198,
    MAXOpcodeProfileDelete = 199,
    MAXOpcodeProfileDeleteTime = 200,
    MAXOpcodeAuthQrApprove = 290,
    MAXOpcodeChatSuggest = 300,
    MAXOpcodeBannersSync = 302,

    // Опросы
    MAXOpcodeSendVote = 304,
    MAXOpcodeVotersListByAnswer = 305,
    MAXOpcodeGetPollUpdates = 306,

    // Папки
    MAXOpcodeFoldersGet = 272,
    MAXOpcodeFoldersGetById = 273,
    MAXOpcodeFoldersUpdate = 274,
    MAXOpcodeFoldersReorder = 275,
    MAXOpcodeFoldersDelete = 276,

    // Истории
    MAXOpcodeStoriesList = 208,
    MAXOpcodeStoriesListByOwner = 209,
    MAXOpcodeStoriesGetByOwner = 210,
    MAXOpcodeStoriesGetStats = 211,
    MAXOpcodeStoriesGetDetailedStats = 212,
    MAXOpcodeStoriesReact = 213,
    MAXOpcodeStoriesMark = 214,
    MAXOpcodeStoriesSend = 215,
    MAXOpcodeNotifStoriesUpdate = 216,
    MAXOpcodeStoriesEdit = 217,
    MAXOpcodeStoriesDelete = 218,
    MAXOpcodeStoriesGetByStoryId = 220
};

/// Человекочитаемое имя опкода для логов.
NSString *MAXOpcodeName(NSUInteger opcode);

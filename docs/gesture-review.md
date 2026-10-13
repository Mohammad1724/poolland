# بررسی تخصصی: باز و بسته شدن پنجره‌ها و شیت‌ها با ژست

تاریخ: ۲۰۲۶-۱۰-۱۳ · نسخه بررسی‌شده: `1.3.0+4` · پایه: `da095fb` (main)

وضعیت: `flutter analyze` بدون خطا و هر **۲۵۱ آزمون** سبز (CI روی PR شماره ۷).

این سند نتیجه یک دیباگ ریشه‌ای روی همه مسیرهایی است که یک صفحه یا یک شیت
با ژست باز یا بسته می‌شود: گذار صفحه، درگ برای بستن شیت، overscroll،
`Dismissible`، `SwipeActions`، منوی شعاعی FAB و تور ژست‌ها.

## روش کار

هیچ حدسی زده نشده. برای هر ادعا، سورس خود فریم‌ورک Flutter در همان
revision ای که `.metadata` پروژه ثبت کرده
(`5fc346839b5d0eef006ed8404392afb4dfae428d`) خوانده شد:

`animation/animations.dart` · `widgets/routes.dart` · `widgets/navigator.dart`
· `widgets/scroll_position.dart` · `widgets/scroll_position_with_single_context.dart`
· `widgets/scroll_physics.dart` · `widgets/scroll_notification.dart`
· `widgets/draggable_scrollable_sheet.dart` · `material/bottom_sheet.dart`
· `material/page_transitions_theme.dart` · `widgets/dismissible.dart`
· `gestures/velocity_tracker.dart` · `gestures/lsq_solver.dart` · `widgets/pop_scope.dart`
· `gestures/monodrag.dart` · `gestures/recognizer.dart` · `gestures/pointer_router.dart`
· `gestures/constants.dart` · `widgets/gesture_detector.dart` · `material/dialog.dart`

نقشه فراخوانی ژست‌ها در کد برنامه هم کامل استخراج شد: ۱۴ فراخوانی
`showLedgerSheet`، ۹ فراخوانی `showDialog`، ۳ `DraggableScrollableSheet`،
۱ `Dismissible`، ۴ مصرف‌کننده `SwipeActions` و یک منوی شعاعی.

## باگ‌های پیدا شده

### ۱. نشت `CurvedAnimation` در هر فریم گذار (بحرانی)

`_ModalScopeState.build` گذار را داخل
`ListenableBuilder(listenable: Listenable.merge([route.animation, route.secondaryAnimation]))`
می‌سازد، یعنی `buildTransitions` و `transitionBuilder` **در هر فریم** صدا زده
می‌شوند. هر دو در این پروژه داخل خودشان `CurvedAnimation` می‌ساختند، و
سازنده `CurvedAnimation` همیشه `parent.addStatusListener(_updateCurveDirection)`
را صدا می‌کند. خود داکیومنت Flutter در `animations.dart` صراحتاً می‌گوید این
آبجکت باید یک بار (مثلاً در `initState`) ساخته و dispose شود و هرگز در build
ساخته نشود.

نتیجه: در هر push چیزی بین ۱۹ تا ۳۸ listener روی انیمیشن route ثبت می‌شد و
هیچ‌وقت پاک نمی‌شد. بدتر از آن، route **زیرین** هم از راه
`secondaryAnimation` listener جمع می‌کرد، پس یک route ماندگار مثل `HomeShell`
بی‌نهایت بزرگ می‌شد و jank به‌مرور زیاد می‌شد.

**رفع:** هر دو گذار به `StatefulWidget` منتقل شدند (`_LedgerPageTurn` و
`_LedgerSheetTransition`) که `CurvedAnimation`ها را یک بار با `late final`
می‌سازند و در `dispose` آزاد می‌کنند. ضمناً
`MediaQuery.maybeOf(ctx)?.disableAnimations` به `Motion.reduced(ctx)` تبدیل شد
که aspect-scoped است، تا باز شدن کیبورد باعث rebuild گذار نشود.

مرجع: `page_transitions_theme.dart` در خود فریم‌ورک هم همین کار را می‌کند —
`_FadeForwardsPageTransition` از `Animatable`های static و `CurveTween` استفاده
می‌کند و هیچ `CurvedAnimation`ی در آن فایل نیست.

### ۲. کشیدن شیت به پایین روی فیزیک bouncing کار نمی‌کرد (بحرانی)

پیاده‌سازی قبلی فقط به `OverscrollNotification` گوش می‌داد. اما
`BouncingScrollPhysics.applyBoundaryConditions` همیشه `0.0` برمی‌گرداند
(`scroll_physics.dart:754`)، پس overscroll هرگز گزارش نمی‌شود؛ به‌جایش خودِ
`pixels` منفی می‌شود و `ScrollUpdateNotification` با `outOfRange: true` صادر
می‌شود. یعنی روی iOS، macOS و Safari-iOS شیت **اصلاً** با کشیدن بسته
نمی‌شد.

روی فیزیک clamping برعکس مشکل داشت: یک `OverscrollNotification` (یعنی عبور
از touch slop، حدود ۱۸ پیکسل) کافی بود تا شیت pop شود. بدون آستانه، بدون
فیدبک و بدون امکان انصراف → بسته شدن تصادفی با یک لمس لغزان.

**رفع:** `_OverscrollDismiss` با `_SheetPullDismiss` جایگزین شد که هر دو
مسیر را می‌خواند: `OverscrollNotification` برای clamping (تجمعی) و
`ScrollUpdateNotification` با `outOfRange` برای bouncing (مطلق)، و هنگام
بالا رفتن دوباره، pull را پیکسل‌به‌پیکسل پس می‌دهد.

### ۳. شیت وتوشده برای همیشه بیرون صفحه گیر می‌کرد (بحرانی)

`_SheetDragDismiss._onEnd` بدون ریست کردن `_dy` پاپ می‌کرد. اگر یک
`PopScope` جلوی pop را می‌گرفت، شیت تا ابد نیمه بیرون صفحه می‌ماند و هیچ
ژستی برای برگرداندنش وجود نداشت (چون `_closing` هم `true` لچ می‌شد).

**رفع:** موتور درگ کامل بازنویسی شد: `_SheetDismiss` + `_SheetDismissScope` +
`_SheetDismissState`. یک pull مشترک که هم از نوار گرفتن ۳۴ پیکسلی و هم از
اسکرول‌شدنی خود شیت تغذیه می‌شود؛ آستانه ۱۱۰ پیکسل؛ فلینگ با
`VelocityTracker` مستقل (چون `ScrollEndNotification.dragDetails` در فلینگ‌ها
`null` است و قابل اتکا نیست)؛ گیت `_pointerDown` تا اسکرول چرخ ماوس یا
دنباله بالستیک شیت را معلق نگذارد؛ و در `_dismiss()` بررسی
`route.popDisposition == RoutePopDisposition.doNotPop` که در صورت وتو
`route.onPopInvokedWithResult(false, null)` را صدا می‌کند و شیت را برمی‌گرداند.

### ۴. شیت‌های `DraggableScrollableSheet` با درگ بسته نمی‌شدند (مهم)

`_PickSheet` و `_QuickManagerSheet` روی `DraggableScrollableSheet` ساخته شده‌اند
ولی `showLedgerSheet` یک dialog route خام است. منطق «رسیدن به حداقل اندازه =
بستن» در `_BottomSheetState.extentChanged` زندگی می‌کند
(`material/bottom_sheet.dart:325-330`) که فقط زیر `showModalBottomSheet` وجود
دارد. `DraggableScrollableSheet` خودش هرگز pop نمی‌کند.

**رفع:** `_LedgerSheetFrame` یک
`NotificationListener<DraggableScrollableNotification>` اضافه می‌کند و وقتی
`shouldCloseOnMinExtent && extent <= minExtent` شد، route را pop می‌کند.

### ۵. هیچ اسکرول‌شدنی تودرتویی تفکیک نمی‌شد (مهم)

هر `ListView` عمودی که بالای خودش بود می‌توانست کل شیت را ببندد.

**رفع:** `n.depth != 0` و محور غیرعمودی نادیده گرفته می‌شوند
(`ScrollNotification.depth` به ازای هر `ScrollableState` یکی اضافه می‌شود).

### ۶. `isDismissible: false` فقط barrier را می‌بست (مهم)

درگ به پایین و دکمه back همچنان شیت را می‌بستند.

**رفع:** علاوه بر `barrierDismissible`، یک `PopScope<Object?>(canPop: false)`
اضافه می‌شود و `enabled: false` به هر دو تشخیص‌دهنده درگ داده می‌شود.
(`_ModalScopeStatus` جنریک نیست و `PopScope` با `ModalRoute<dynamic>` کار
می‌کند، پس `Object?` بدون توجه به `T` شیت ثبت می‌شود.)

### ۷. ارتفاع شیت نسبت به کل صفحه حساب می‌شد، نه فضای قابل‌دیدن (مهم)

`pageBuilder` ارتفاع را به `0.92 * MediaQuery.sizeOf(ctx).height` محدود
می‌کرد و هیچ inset ای اعمال نمی‌شد. با کیبورد باز، محتوا + کیبورد از سقف
بیشتر می‌شد (RenderFlex overflow و دکمه Save غیرقابل‌دسترس روی صفحه‌های
کوتاه)، و فیلد جست‌وجوی `_PickSheet` زیر کیبورد پنهان می‌شد. از آن طرف هر شیت
مجبور بود دستی `viewInsets` را padding بدهد، که در ۶ جا تکرار شده بود و
در `_PickSheet` هم اصلاً وجود نداشت.

**رفع:** `_LedgerSheetFrame` یک `StatelessWidget` جداست (چون `pageBuilder` فقط
یک بار اجرا می‌شود ولی این باید با تغییر `MediaQuery` بازسازی شود):
`bottom = max(viewInsets.bottom, viewPadding.bottom)`،
`visible = max(0, size.height - bottom)`، `maxHeight = visible * 0.92`، به
علاوه `Padding(bottom)` و `MediaQuery.removePadding(removeBottom: true)` تا
`SafeArea`های داخلی دوباره همان فضا را اضافه نکنند. هر شش padding دستی حذف
شدند؛ `viewInsets` در کل `lib/` فقط در همین یک جا باقی مانده.

### ۸. ردیف سوایپ‌شده کامل بیرون صفحه پارک می‌شد (مهم)

`Dismissible._updateMoveAnimation` تا `Offset(_dragExtent.sign, …)` توئین
می‌کند و `_handleMoveCompleted` منتظر `_confirmStartResizeAnimation()`
می‌ماند. یعنی تا وقتی `confirmDismiss` در حال `await showPaymentSheet(...)`
یا `await Navigator.push(...)` بود، ردیف یک عرض کامل بیرون صفحه می‌ماند —
و چون background داخل clip ردیف است، پشت barrier نیمه‌شفاف فقط یک شکاف
رنگی دیده می‌شد.

**رفع:** هلپر `afterSwipeSnapBack(context, action)` در `widgets.dart` اضافه شد
(post-frame callback + `context.mounted`)؛ `confirmDismiss` حالا
`Future.value(false)` برمی‌گرداند و اکشن بعد از برگشت فنر اجرا می‌شود. در
`customers_page.dart` و `transactions_page.dart` اعمال شد.

### ۹. منوی شعاعی FAB (متوسط)

* `_SpeedDialLayer` بعد از pointer-down اصلی درج می‌شود، پس hit-test آن
  pointer از قبل کش شده و `onTap` آیتم‌ها و `onBarrier` با همان انگشت
  هرگز اجرا نمی‌شوند. کامنت «یا مستقیم روی یک گزینه بزنید» گمراه‌کننده بود؛
  اصلاح شد (این مسیرها برای انگشت دوم زنده‌اند و حذف نشدند).
* `_onFabLongPressMove` با `break` روی **اولین** اسلات داخل شعاع قفل
  می‌کرد؛ چون `_dialSlot` اسلات‌ها را به لبه‌های صفحه clamp می‌کند، روی
  صفحه‌های کوچک دو اسلات داخل یک شعاع ۵۸ پیکسلی می‌افتادند و گزینه غلط
  انتخاب می‌شد. حالا نزدیک‌ترین برنده است.
* لانگ‌پرس دوم یک `OverlayEntry` تازه روی قبلی درج می‌کرد و `_dialEntry`
  بازنویسی می‌شد → entry قبلی دیگر هیچ‌وقت قابل حذف نبود (نشت).
* منو از مرکز FAB باز نمی‌شد بلکه از نقطه انگشت؛ روی FAB عریض تا ~۳۰
  پیکسل اختلاف داشت.
* `_fan.forward()` به reduced-motion احترام نمی‌گذاشت.
* عوض کردن تب با منوی باز، منو را باز می‌گذاشت.
* FAB پنهان‌شده در ۲۲۰ میلی‌ثانیه‌ای که کوچک می‌شد همچنان قابل لمس بود.

همه رفع شدند (`_fabCenter()`, `_dialPickRadius`, `IgnorePointer`,
`didChangeDependencies` برای `_fan`).

### ۱۰. تور ژست‌ها سازگار نبود (کم)

شیتی که «هر شیتی را به پایین بکشید تا بسته شود» را آموزش می‌داد، خودش روی
`showModalBottomSheet` بود و مکانیزم بستن متفاوتی داشت و دستی `viewInsets`
padding می‌داد. به `showLedgerSheet` مهاجرت کرد (با `Container` سطح و
`Radii.sheet` مطابق بقیه شیت‌ها).

### ۱۱. بدنه چند شیت اسکرول‌نشدنی بود (کم، اما بعد از رفع ۷ مهم شد)

وقتی سقف ارتفاع به فضای واقعاً قابل‌دیدن محدود شد، `Column`های ثابت با
کیبورد باز سرریز می‌کنند. `_PaymentSheet` و `QuickAmountSheet` حالا
`SingleChildScrollView` دارند (`_BudgetSheet`، `_RecurringSheet`،
`SmsReviewSheet` و `_QuickEditPage` از قبل داشتند).

## دور دوم: باگ‌های سطح ویجت

پس از یکسان‌سازی مسیرهای شیت، همان نگاه ریشه‌ای روی خود ویجت‌های ژست
(`_SheetDismiss`، `_SheetPullDismiss`، `SwipeActions`، نوار ناوبری و شیت‌های
کوچک) تکرار شد. نتیجه:

### ۱۲. گرفتن مجدد شیت وسط انیمیشن، آن را جابه‌جا می‌کرد (بحرانی)

`_pull` مقدار **هدف** است و `pull` مقداری که فنر همین لحظه نشان می‌دهد.
`addPull` و `reducePull` فنر را `stop()` می‌کردند و بعد `_pull ± delta` را
می‌نوشتند — یعنی اگر کاربر شیتی را که در حال برگشت بود دوباره بگیرد، شیت
به جای ادامه از همان‌جا که دیده می‌شد، به مقصدی که داشت به آن می‌رفت
پرتاب می‌شد. حالا `_adopt()` اول مقدار جاری فنر را می‌خواند، فنر را
نگه می‌دارد و همان را در `_pull` می‌گذارد.

### ۱۳. مسیر bouncing مقدار مطلق می‌گذاشت، نه delta (بحرانی)

`_SheetPullDismiss` برای فیزیک bouncing از `n.metrics.minScrollExtent -
n.metrics.pixels` استفاده می‌کرد. اگر انگشت وسط برگشت فنر دوباره پایین
بیاید، آن تفاضل ناگهان عددی بی‌ربط به وضعیت قبلی می‌شود و شیت پرش می‌کند؛
ضمن اینکه هر بار محتوای بالای لیست به بالای خودش برگردد، شیت به سقف
پرتاب می‌شد. هر دو فیزیک حالا یک مسیر دارند: تجمع delta
(`setPull` کاملاً حذف شد).

### ۱۴. نوار گرفتن، درگ رو به بالا را می‌دزدید (مهم)

نوار ۳۴ پیکسلی در Stack بالاتر از محتوای شیت است، پس زودتر از لیست به
میدان ژست می‌رسد. یک `VerticalDragGestureRecognizer` معمولی نمی‌تواند بگوید
«فقط پایین»؛ میدان را می‌برد و بعد با حرکت رو به بالا هیچ کاری نمی‌کند —
یعنی فلیکی که از روی دستگیره شروع شود هرگز لیست را اسکرول نمی‌کرد.
`_DownOnlyDrag` (زیرکلاس همان recognizer) در `handleEvent` به محض اینکه
نشانگر بیش از `kTouchSlop` رو به بالا رفته باشد `resolve(rejected)` صدا
می‌کند تا ژست به لایه زیر برگردد. `_settled` تضمین می‌کند این تصمیم برای
هر اشاره‌گر دقیقاً یک بار گرفته شود.

### ۱۵. همان پرش در `SwipeActions` (مهم)

`_onUpdate` هم `_snap.stop()` می‌کرد و بعد از `_open` (هدف) ادامه می‌داد.
`_adopt()` معادلش اینجا اضافه شد.

### ۱۶. فلیک برای بستن ردیف باز کار نمی‌کرد (مهم)

شرط قدیمی `if (_open > 0.5 || v > 600)` بود. ردیفی که باز است `_open == 1`
دارد، پس فلیک برگشتی هم آن را دوباره باز می‌کرد: تا وقتی درگ از نصف `panelWidth` نگذشته باشد، سرعت هیچ نقشی نداشت. حالا `v < -600` اول
بررسی می‌شود و در هر دو جهت فلیک تصمیم‌گیرنده است.

### ۱۷. دکمه‌های پنل ~۱۶۰ میلی‌ثانیه مرده بودند (مهم)

`_SwipeButton` با `enabled: raw >= 0.99` ساخته می‌شد که `raw` مقدار
**انیمیت‌شده** است. یعنی بعد از باز شدن ردیف، تا پایان انیمیشن ۲۰۰
میلی‌ثانیه‌ای (با `easeOutCubic` حدود ۱۶۰ms) دکمه‌ها ضربه نمی‌گرفتند —
سوایپ سریع و بلافاصله ضربه، هیچ کاری نمی‌کرد. حالا `enabled` از روی
`_open` (هدف) خوانده می‌شود.

### ۱۸. ردیف باز، باز می‌ماند؛ چند ردیف همزمان باز می‌شد (مهم)

هیچ مکانیزمی برای بستن ردیف جز ضربه به خودش وجود نداشت. باز کردن ردیف دوم،
ردیف اول را باز نگه می‌داشت. حالا یک `addGlobalRoute` روی
`WidgetsBinding.instance.pointerRouter` فقط تا وقتی ردیف باز است ثبت می‌شود
و هر `PointerDownEvent` بیرون از `paintBounds` خودش، ردیف را می‌بندد.
ضربه‌های داخل خود ردیف (از جمله روی دکمه‌های پنل) نادیده گرفته می‌شوند.
`PointerRouter.route` قبل از پخش، نقشه را کپی می‌کند
(`pointer_router.dart:126-143`)، پس حذف route از داخل همان callback امن است.

### ۱۹. دکمه back سیستم، صفحه را می‌بست نه ردیف را (مهم)

`SwipeActions` حالا در `PopScope(canPop: _open < 0.99)` پیچیده شده و در
`onPopInvokedWithResult` ردیف را می‌بندد. خود `PopScope` همیشه در درخت است:
وارد و خارج کردن شرطی‌اش، ردیف زیرش را remount می‌کرد و `EnterMotion`
دوباره اجرا می‌شد. چون در هر لحظه حداکثر یک ردیف باز است (باگ ۱۸)، حداکثر
یک `PopScope` از pop جلوگیری می‌کند.

### ۲۰. `transactions_page` تنها جای ناسازگار بود (مهم)

این صفحه `Dismissible` داشت (راست = ویرایش، چپ = تکرار، بدون حذف) در حالی
که dashboard و personal و customer-detail از `SwipeActions` +
`txnSwipeActions` (ویرایش/تکرار/حذف) استفاده می‌کنند. یعنی جملهٔ تور ژست
فقط در ۳ مورد از ۴ درست بود. حالا هر چهار جا یک ویجت و یک مجموعه اکشن
دارند و جملهٔ تور همه‌جا صادق است. ضربه روی ردیف همچنان ویرایش را باز
می‌کند، پس از دست رفتن سوایپ چپ‌به‌راست چیزی کم نمی‌کند. `phase3_gestures_test.dart`
برای همین بازنویسی شد.

### ۲۱. نوار ناوبری: Tooltip رقیب و ناحیه ضربه متورم (متوسط)

هر سلول `Tooltip(message: dest.label)` داشت در حالی که همان label زیر
آیکون چاپ می‌شود و در `Semantics(label:)` هم هست؛ تنها اثرش یک
`LongPressGestureRecognizer` بود که در میدان ژست هر سلول رقابت می‌کرد.
`Transform.scale(scale: 1 + 0.22 * bounce)` هم **بیرون** `InkWell` بود:
برای ۲۷۳ میلی‌ثانیه‌ای که bounce جریان دارد، ناحیه ضربه سلول ۲۲٪ بزرگ
می‌شود و داخل همسایه‌هایش می‌رود. حالا scale روی محتوای سلول اعمال
می‌شود و ناحیه ضربه همیشه دقیقاً یک سلول است.

### ۲۲. دکمه Record در `QuickAmountSheet` بی‌اثر بود (متوسط)

`onPressed` همیشه متصل بود و داخلش `if (v <= 0) return;` — یعنی با مبلغ
خالی، شیت فقط بسته نمی‌شد و هیچ توضیحی هم نمی‌داد. حالا دکمه تا وقتی مبلغ
معتبر نباشد غیرفعال است (`AnimatedBuilder` روی خود کنترلر). اسنک‌بار
«اول مبلغ وارد کنید» عمداً اضافه نشد: کلید localization جدید می‌خواست و
`localization_guard_test.dart` را می‌شکست.

### ۲۳. دستگیره دست‌ساز در `_PaymentSheet` (کم)

یک `Container` ۴۲×۴ با `theme.dividerColor` جای `SheetHandle` (۴۴×۴،
`onSurface@0.22`) را گرفته بود. حذف شد تا همه شیت‌ها یک دستگیره داشته باشند.

### ۲۴. کامنت مستندات جابه‌جا نشسته بود (کم)

بلوک «Copy on long-press» بالای `SheetHandle` بود و `CopyMoney` بدون
توضیح می‌ماند. سر جایش برگشت.

## موارد بررسی‌شده که باگ نیستند

* `theme.dart:49-56` واقعاً `LedgerPageTransitionsBuilder` را برای هر پنج
  پلتفرم ثبت می‌کند.
* هر دو `Dismissible` همیشه `false` برمی‌گردانند → حذف تصادفی ممکن نیست،
  کلیدها پایدارند و `_confirming` جلوی درگ مجدد را می‌گیرد.
* `txn_actions.dart` بعد از هر `await` یک `context.mounted` دارد و حذف با
  اسنک‌بار Undo پنج ثانیه‌ای همراه است.
* `_dialHighlight.dispose()` بعد از `_closeDial()` امن است؛ `AppLockGate` از
  `Visibility` استفاده می‌کند پس `HomeShell` هنگام قفل unmount نمی‌شود، و
  چون `MaterialApp.builder` دور `Navigator` می‌پیچد، صفحه قفل روی اورلی منو
  نقاشی می‌شود.
* هر ۱۲ رشته تور ژست کلید localization دارند.
* **۹ فراخوانی `showDialog` باگ نیستند.** سه دلیل، هر سه از سورس خوانده شد:
  `theme.dart:222` از قبل `DialogThemeData` دارد (گوشه ۲۰، فونت وزیرمتن برای
  عنوان و متن)؛ خود `Dialog` در `material/dialog.dart:268` مقدار
  `MediaQuery.viewInsetsOf(context) + insetPadding` را جمع می‌کند پس کیبورد
  دیالوگ را هل می‌دهد؛ و `_buildMaterialDialogTransitions` در stable فعلی فقط
  `return child;` است — `CurvedAnimation` داخل state نگهداری و dispose
  می‌شود، یعنی نشتی که در باگ ۱ پیدا شد اینجا وجود ندارد. بسته شدن با
  barrier و دکمه back هم کار می‌کند. تبدیل دیالوگ‌های کوتاه ورودی/تأیید و
  تقویم جلالی به شیت کشیدنی، پس‌رفت از زبان Material است نه اصلاح باگ.

## چیزی که عمداً تغییر نکرد

* دیالوگ‌ها (۹ مورد) شیت نشدند — دلایلش در بخش قبل آمد.
* `TextEditingController`های ساخته‌شده داخل دیالوگ‌های `settings_page`
  dispose نمی‌شوند. dispose در `then(...)` یعنی وسط گذار خروجی، و خطرش از
  سودش بیشتر است؛ نشتی هم در حد یک کنترلر کوتاه‌عمر است.
* منوی شعاعی FAB با دکمه back بسته نمی‌شود و با pause شدن برنامه هم نه.
  هر دو نیاز به `PopScope` روی ریشه `HomeShell` دارند و رفتار back را برای
  کل پوسته عوض می‌کنند؛ تصمیمش با صاحب محصول است.
* نوار گرفتن ۳۴ پیکسلی همچنان `HitTestBehavior.translucent` دارد و بالاترین
  لایه Stack است، پس دکمه‌های زیرش ضربه می‌خورند. آنچه عوض شد این است که
  دیگر درگ رو به بالا را تصاحب نمی‌کند (باگ ۱۴).

## آزمون‌ها

ده آزمون رگرسیون در `test/motion_test.dart`:

| آزمون | چه باگی را قفل می‌کند |
| --- | --- |
| `closes on a pull-down under bouncing physics` | ۲ |
| `survives a pull below the dismiss threshold` | ۲ (ماشه حساس) |
| `a nested list at its own top leaves the sheet open` | ۵ |
| `a vetoed drag puts the sheet back where it was` | ۳ |
| `a non-dismissible sheet ignores drag and barrier` | ۶ |
| `a draggable sheet closes at its minimum extent` | ۴ |
| (موجود) `closes on a pull-down at the top` / `ignores a horizontal pull` | ۲ |
| (موجود) `SwipeActions opens on a trailing drag and fires the action` | ۱۷ |
| `SwipeActions folds away when anything else is touched` | ۱۸ |
| `SwipeActions takes a flick as the decision` | ۱۶ |
| `the system back button closes an open row first` | ۱۹ |

`test/flutter_test_config.dart` مقدار `Motion.motionEnabled = false` را
می‌گذارد، پس در آزمون‌ها فنر و گذار instant هستند و نتیجه قطعی است.
`tester.drag` هیچ timeStamp ای پاس نمی‌دهد، پس `LeastSquaresSolver.solve()`
با determinant صفر `null` می‌دهد و `getVelocity()` صفر برمی‌گرداند — یعنی
در آزمون‌های درگ، تصمیم فقط از روی آستانه pull گرفته می‌شود، نه سرعت.

برای سرعت واقعی فقط `tester.fling` می‌ماند، و آن هم دام دارد: `flingFrom`
مسیر را روی **۵۱ رویداد move** پخش می‌کند
(`controller.dart:1338-1375`) در حالی که `VelocityTracker` فقط **۲۰ نمونه
آخر** را نگه می‌دارد (`kHistorySize`). `isFlingGesture` هم علاوه بر سرعت،
`estimate.offset.dx.abs() > kTouchSlop` می‌خواهد — یعنی همان ۲۰ نمونهٔ آخر.
نتیجه: اگر کل مسیر یک فلیک کمتر از ~۴۶ پیکسل باشد، پنجرهٔ ۲۰ نمونه‌ای زیر
۱۸ پیکسل می‌ماند، فلیک اصلاً فلیک شناخته نمی‌شود و `primaryVelocity` صفر
برمی‌گردد. آزمون‌های فلیک این مجموعه با ۷۰ پیکسل نوشته شده‌اند.

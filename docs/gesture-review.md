# بررسی تخصصی: باز و بسته شدن پنجره‌ها و شیت‌ها با ژست

تاریخ: ۲۰۲۶-۱۰-۱۲ · نسخه بررسی‌شده: `1.3.0+4` · کامیت پایه: `902b9cb`

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

نقشه فراخوانی ژست‌ها در کد برنامه هم کامل استخراج شد: ۱۴ فراخوانی
`showLedgerSheet`، ۹ فراخوانی `showDialog`، ۳ `DraggableScrollableSheet`،
۲ `Dismissible`، ۳ مصرف‌کننده `SwipeActions` و یک منوی شعاعی.

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

## چیزی که عمداً تغییر نکرد

`transactions_page` از `Dismissible` (ویرایش/تکرار، باز کردن صفحه کامل)
استفاده می‌کند در حالی که dashboard، personal و customer-detail از
`SwipeActions` + `txnSwipeActions` (ویرایش/تکرار/حذف). یعنی جمله
«یک ردیف تراکنش را به پهلو بکشید تا ویرایش، تکرار یا حذف شود» فقط در ۳ مورد
از ۴ درست است. یکسان‌سازی یعنی تغییر کلیدهای `lib/core/localization.dart` و
شکستن `phase3_gestures_test.dart`؛ خارج از دامنه این دیباگ است.

همچنین نوار گرفتن ۳۴ پیکسلی در Stack بالاترین است، پس درگ **رو به بالا**
از همان نوار، لیست را اسکرول نمی‌کند. این همان رفتار شیت‌های iOS است
(ناحیه دستگیره به شیت تعلق دارد نه به محتوا) و عمداً نگه داشته شد؛ نوار
`HitTestBehavior.translucent` دارد، پس دکمه‌های زیرش همچنان ضربه می‌خورند.

## آزمون‌ها

هفت آزمون رگرسیون در `test/motion_test.dart`:

| آزمون | چه باگی را قفل می‌کند |
| --- | --- |
| `closes on a pull-down under bouncing physics` | ۲ |
| `survives a pull below the dismiss threshold` | ۲ (ماشه حساس) |
| `a nested list at its own top leaves the sheet open` | ۵ |
| `a vetoed drag puts the sheet back where it was` | ۳ |
| `a non-dismissible sheet ignores drag and barrier` | ۶ |
| `a draggable sheet closes at its minimum extent` | ۴ |
| (موجود) `closes on a pull-down at the top` / `ignores a horizontal pull` | ۲ |

`test/flutter_test_config.dart` مقدار `Motion.motionEnabled = false` را
می‌گذارد، پس در آزمون‌ها فنر و گذار instant هستند و نتیجه قطعی است.
`tester.drag` هیچ timeStamp ای پاس نمی‌دهد، پس `LeastSquaresSolver.solve()`
با determinant صفر `null` می‌دهد و `getVelocity()` صفر برمی‌گرداند — یعنی
تصمیم فقط از روی آستانه pull گرفته می‌شود، نه سرعت.

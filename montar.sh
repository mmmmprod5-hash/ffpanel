chmod +x montar.sh && ./montar.sh
#!/usr/bin/env bash
set -euo pipefail
DIR="ffmenu"
rm -rf "$DIR"; mkdir -p "$DIR"
cd "$DIR"

cat > control <<'EOF'
Package: com.venice.ffmenu
Name: FF Menu
Version: 0.1
Architecture: iphoneos-arm
Description: panel holograma + aim
Maintainer: tu
Author: tu
Section: Tweaks
Depends: mobilesubstrate
EOF

cat > Makefile <<'EOF'
TARGET := iphone:clang:latest:14.0
ARCHS = arm64
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = FFMenu
FFMenu_FILES = Tweak.xm
FFMenu_CFLAGS = -fobjc-arc
FFMenu_FRAMEWORKS = UIKit Foundation QuartzCore
FFMenu_PRIVATE_FRAMEWORKS = IOKit
include $(THEOS)/makefiles/tweak.mk
EOF

cat > Tweak.xm <<'EOF'
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <IOKit/hid/IOHIDEvent.h>
#import <IOKit/hidsystem/IOHIDEventSystemClient.h>
#import <dlfcn.h>
#import <unistd.h>
#import <math.h>

// ===================== CONFIGURA AQUÍ =====================
// Saca estos tres datos de dump.cs (Il2CppDumper)
#define K_PLAYER_NS  ""          // namespace de la clase jugador
#define K_PLAYER     "Player"    // nombre de la clase jugador
#define BONE_HEAD    "Head"      // nombre real del hueso cabeza
#define BONE_NECK    "Neck"
#define BONE_CHEST   "Chest"
// =========================================================

typedef void   *(*f_dg)(void);
typedef void  **(*f_dga)(void *, size_t *);
typedef void   *(*f_ai)(void *);
typedef void   *(*f_cfn)(void *, const char *, const char *);
typedef void   *(*f_cgm)(void *, const char *, int);
typedef void   *(*f_ri)(void *, void *, void **, void **);
typedef void   *(*f_cgt)(void *);
typedef void   *(*f_tgo)(void *);
typedef void   *(*f_snew)(const char *);

static f_dg p_dg; static f_dga p_dga; static f_ai p_ai;
static f_cfn p_cfn; static f_cgm p_cgm; static f_ri p_ri;
static f_cgt p_cgt; static f_tgo p_tgo; static f_snew p_snew;

static void *gKObj, *gKTr, *gKComp, *gKCam, *gKPlayer;
static void *mGetPos, *mFind, *mGetTr, *mW2S, *mGetMain, *mFindObjs;

static BOOL resolve(void) {
    void *h = dlopen("@rpath/UnityFramework.framework/UnityFramework", RTLD_NOW);
    if (!h) h = dlopen("/usr/lib/libil2cpp.so", RTLD_NOW);
    if (!h) return NO;
    #define R(n) if (!(p_##n = (void *)dlsym(h, "il2cpp_" #n))) return NO;
    R(dg) R(dga) R(ai) R(cfn) R(cgm) R(ri)
    if (!(p_cgt = (void *)dlsym(h, "il2cpp_class_get_type"))) return NO;
    if (!(p_tgo = (void *)dlsym(h, "il2cpp_type_get_object"))) return NO;
    if (!(p_snew = (void *)dlsym(h, "il2cpp_string_new"))) return NO;
    #undef R
    return YES;
}

static void *klass(const char *ns, const char *name) {
    size_t n = 0;
    void **a = p_dga(p_dg(), &n);
    for (size_t i = 0; i < n; i++) {
        void *k = p_cfn(p_ai(a[i]), ns, name);
        if (k) return k;
    }
    return NULL;
}

typedef struct { float x, y, z; } V3;

static V3 unbox(void *o) {
    V3 v = {0, 0, 0};
    if (!o) return v;
    float *f = (float *)((char *)o + 0x10);
    v.x = f[0]; v.y = f[1]; v.z = f[2];
    return v;
}

static V3 pos_of(void *transform) {
    if (!transform || !mGetPos) return (V3){0,0,0};
    return unbox(p_ri(mGetPos, transform, NULL, NULL));
}

static void *child(void *transform, const char *name) {
    if (!transform || !mFind || !p_snew) return NULL;
    void *s = p_snew(name);
    return p_ri(mFind, transform, (void *[]){s}, NULL);
}

static void *transform_of(void *comp) {
    if (!comp || !mGetTr) return NULL;
    return p_ri(mGetTr, comp, NULL, NULL);
}

static int list_players(void ***out) {
    if (!mFindObjs || !gKPlayer) return 0;
    void *t = p_tgo(p_cgt(gKPlayer));
    if (!t) return 0;
    void *arr = p_ri(mFindObjs, NULL, (void *[]){t}, NULL);
    if (!arr) return 0;
    uint64_t len = *(uint64_t *)((char *)arr + 0x18);
    *out = (void **)((char *)arr + 0x20);
    return (int)len;
}

static CGPoint w2s(void *cam, V3 w) {
    if (!cam || !mW2S) return CGPointMake(-1, -1);
    V3 v = w;
    void *r = p_ri(mW2S, cam, (void *[]){&v}, NULL);
    if (!r) return CGPointMake(-1, -1);
    V3 s = unbox(r);
    if (s.z < 0) return CGPointMake(-1, -1);
    return CGPointMake(s.x, UIScreen.mainScreen.bounds.size.height - s.y);
}

static BOOL gHolo = YES, gAim = NO, gTap = NO;
static float gFov = 140, gSmooth = 42, gDelay = 0.08f;
static NSString *gBone = @BONE_HEAD;

static IOHIDEventSystemClientRef gClient;
static void inject(CGPoint p) {
    if (!gClient) gClient = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault);
    if (!gClient) return;
    IOHIDEventRef e = IOHIDEventCreateDigitizerEvent(
        kCFAllocatorDefault, mach_absolute_time(),
        kIOHIDDigitizerTransducerTypeFinger, 0, 0,
        kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch,
        0, p.x, p.y, 0, 1.0f, 0, true, true, kIOHIDEventOptionNone);
    IOHIDEventSystemClientDispatchEvent(gClient, e);
    CFRelease(e);
}

@interface FFView : UIView @end
@implementation FFView

- (void)drawRect:(CGRect)r {
    CGContextRef c = UIGraphicsGetCurrentContext();
    void **list; int n = list_players(&list);
    if (n <= 0) return;
    void *cam = p_ri(mGetMain, NULL, NULL, NULL);
    if (!cam) return;

    CGPoint ctr = CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r));
    CGPoint best = CGPointMake(-1, -1);
    float bestD = gFov;

    for (int i = 0; i < n; i++) {
        if (!list[i]) continue;
        void *tr = transform_of(list[i]);
        V3 hp = pos_of(child(tr, gBone.UTF8String));
        if (hp.x == 0 && hp.y == 0 && hp.z == 0) continue;
        CGPoint s = w2s(cam, hp);
        if (s.x < 0) continue;

        if (gHolo) {
            CGContextSetStrokeColorWithColor(c, UIColor.orangeColor.CGColor);
            CGContextSetLineWidth(c, 1.5);
            CGContextStrokeRect(c, CGRectMake(s.x - 18, s.y - 34, 36, 68));
            CGContextStrokeEllipseInRect(c, CGRectMake(s.x - 6, s.y - 6, 12, 12));
        }

        if (gAim) {
            float d = hypotf(s.x - ctr.x, s.y - ctr.y);
            if (d < bestD) { bestD = d; best = s; }
        }
    }

    if (gAim && best.x >= 0) {
        float k = gSmooth / 100.0f;
        CGPoint to = CGPointMake(ctr.x + (best.x - ctr.x) * k,
                                 ctr.y + (best.y - ctr.y) * k);
        inject(to);
        if (gTap) { usleep((useconds_t)(gDelay * 1e6f)); inject(to); }
    }
}
@end

static UIWindow *gWin;
static FFView *gView;
static CADisplayLink *gLink;
static UIButton *gBtn;
static UIWindow *gPanel;

@interface FFMenu : NSObject
@property (nonatomic, strong) UIWindow *panel;
@end

@implementation FFMenu

- (void)holo:(UISwitch *)s { gHolo = s.on; }
- (void)aim:(UISwitch *)s  { gAim = s.on; }
- (void)tap:(UISwitch *)s  { gTap = s.on; }
- (void)fov:(UISlider *)s  { gFov = s.value; }
- (void)smo:(UISlider *)s  { gSmooth = s.value; }
- (void)bone:(UISegmentedControl *)s {
    NSArray *b = @[@"Head", @"Neck", @"Chest"];
    gBone = b[s.selectedSegmentIndex];
}
- (void)close { gPanel.hidden = YES; gPanel = nil; }

- (void)pan:(UIPanGestureRecognizer *)g {
    CGPoint d = [g translationInView:g.view];
    g.view.center = CGPointMake(g.view.center.x + d.x, g.view.center.y + d.y);
    [g setTranslation:CGPointZero inView:g.view];
}

- (UILabel *)lbl:(NSString *)t size:(CGFloat)sz {
    UILabel *l = [UILabel new];
    l.text = t;
    l.font = [UIFont boldSystemFontOfSize:sz];
    l.textColor = UIColor.whiteColor;
    return l;
}

- (UISwitch *)sw:(BOOL)on sel:(SEL)a {
    UISwitch *s = [UISwitch new];
    s.on = on;
    [s addTarget:self action:a forControlEvents:UIControlEventValueChanged];
    return s;
}

- (UIStackView *)row:(NSString *)t ctl:(UIView *)c {
    UIStackView *h = [[UIStackView alloc] initWithArrangedSubviews:@[[self lbl:t size:12], c]];
    h.axis = UILayoutConstraintAxisHorizontal;
    h.distribution = UIStackViewDistributionEqualSpacing;
    h.alignment = UIStackViewAlignmentCenter;
    return h;
}

- (void)open {
    if (gPanel) return;
    gPanel = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 268, 330)];
    gPanel.center = CGPointMake(UIScreen.mainScreen.bounds.size.width / 2,
                                UIScreen.mainScreen.bounds.size.height / 2);
    gPanel.windowLevel = UIWindowLevelAlert + 2;
    gPanel.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.95];
    gPanel.layer.cornerRadius = 18;
    gPanel.layer.masksToBounds = YES;
    gPanel.hidden = NO;

    UIViewController *vc = [UIViewController new];
    gPanel.rootViewController = vc;

    UIStackView *st = [[UIStackView alloc] initWithFrame:CGRectInset(gPanel.bounds, 16, 16)];
    st.axis = UILayoutConstraintAxisVertical;
    st.spacing = 10;

    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:
        @[[self lbl:@"FF MENU" size:15],
          [self sw:NO sel:@selector(close)]]];
    top.axis = UILayoutConstraintAxisHorizontal;
    top.distribution = UIStackViewDistributionEqualSpacing;
    [st addArrangedSubview:top];

    [st addArrangedSubview:[self row:@"Holograma" ctl:[self sw:gHolo sel:@selector(holo:)]]];
    [st addArrangedSubview:[self row:@"Aimbot"    ctl:[self sw:gAim  sel:@selector(aim:)]]];
    [st addArrangedSubview:[self row:@"One tap"   ctl:[self sw:gTap  sel:@selector(tap:)]]];

    UISlider *f = [UISlider new];
    f.minimumValue = 60; f.maximumValue = 320; f.value = gFov;
    [f addTarget:self action:@selector(fov:) forControlEvents:UIControlEventValueChanged];
    [st addArrangedSubview:[self row:@"FOV" ctl:f]];

    UISlider *s = [UISlider new];
    s.minimumValue = 1; s.maximumValue = 100; s.value = gSmooth;
    [s addTarget:self action:@selector(smo:) forControlEvents:UIControlEventValueChanged];
    [st addArrangedSubview:[self row:@"Suavizado" ctl:s]];

    UISegmentedControl *sg = [[UISegmentedControl alloc] initWithItems:@[@"Head", @"Neck", @"Chest"]];
    sg.selectedSegmentIndex = 0;
    [sg addTarget:self action:@selector(bone:) forControlEvents:UIControlEventValueChanged];
    [st addArrangedSubview:sg];

    [vc.view addSubview:st];
}
@end

static FFMenu *gMenu;

static void setup(void) {
    gKObj    = klass("UnityEngine", "Object");
    gKTr     = klass("UnityEngine", "Transform");
    gKComp   = klass("UnityEngine", "Component");
    gKCam    = klass("UnityEngine", "Camera");
    gKPlayer = klass(K_PLAYER_NS, K_PLAYER);

    if (!gKObj || !gKTr || !gKCam || !gKPlayer) {
        NSLog(@"[FFMenu] clases no encontradas (obj=%p tr=%p cam=%p player=%p)",
              gKObj, gKTr, gKCam, gKPlayer);
        return;
    }

    mGetPos   = p_cgm(gKTr, "get_position", 0);
    mFind     = p_cgm(gKTr, "Find", 1);
    mGetTr    = p_cgm(gKComp, "get_transform", 0);
    mW2S      = p_cgm(gKCam, "WorldToScreenPoint", 1);
    mGetMain  = p_cgm(gKCam, "get_main", 0);
    mFindObjs = p_cgm(gKObj, "FindObjectsOfType", 1);
    NSLog(@"[FFMenu] metodos: pos=%p find=%p tr=%p w2s=%p main=%p objs=%p",
          mGetPos, mFind, mGetTr, mW2S, mGetMain, mFindObjs);

    gWin = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    gWin.windowLevel = UIWindowLevelAlert + 1;
    gWin.backgroundColor = UIColor.clearColor;
    gWin.rootViewController = [UIViewController new];
    gView = [[FFView alloc] initWithFrame:gWin.bounds];
    gView.backgroundColor = UIColor.clearColor;
    gView.opaque = NO;
    gView.userInteractionEnabled = YES;
    [gWin.rootViewController.view addSubview:gView];
    gWin.hidden = NO;

    gLink = [CADisplayLink displayLinkWithTarget:gView selector:@selector(setNeedsDisplay)];
    [gLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];

    gMenu = [FFMenu new];
    gBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    gBtn.frame = CGRectMake(14, 120, 52, 52);
    gBtn.layer.cornerRadius = 26;
    gBtn.backgroundColor = [UIColor colorWithRed:1 green:0.36 blue:0 alpha:0.85];
    [gBtn setTitle:@"FF" forState:UIControlStateNormal];
    [gBtn setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    [gBtn addTarget:gMenu action:@selector(open) forControlEvents:UIControlEventTouchUpInside];
    [gBtn addGestureRecognizer:[[UIPanGestureRecognizer alloc]
        initWithTarget:gMenu action:@selector(pan:)]];
    [gView addSubview:gBtn];

    NSLog(@"[FFMenu] listo");
}

%ctor {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        for (int i = 0; i < 200; i++) {
            if (resolve()) {
                usleep(400000);
                dispatch_async(dispatch_get_main_queue(), ^{ setup(); });
                return;
            }
            usleep(100000);
        }
        NSLog(@"[FFMenu] il2cpp no resuelto");
    });
}
EOF

cat > build.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
IPA="${1:-}"
[ -z "$IPA" ] && { echo "uso: ./build.sh ruta/a/FreeFire.ipa"; exit 1; }
[ -f "$IPA" ] || { echo "no existe: $IPA"; exit 1; }
export THEOS="${THEOS:-$HOME/theos}"
[ -d "$THEOS" ] || { echo "falta Theos en \$THEOS ($THEOS)"; exit 1; }

make clean >/dev/null
make package

DYLIB=$(find .theos/obj -name 'FFMenu.dylib' | head -1)
[ -f "$DYLIB" ] || { echo "no se generó el dylib"; exit 1; }

W=$(mktemp -d)
unzip -q "$IPA" -d "$W"
APP=$(find "$W/Payload" -maxdepth 1 -name '*.app' | head -1)
[ -d "$APP" ] || { echo "IPA sin Payload/*.app"; exit 1; }
EXE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")

cp "$DYLIB" "$APP/"
if command -v insert_dylib >/dev/null 2>&1; then
  insert_dylib --inplace "@executable_path/FFMenu.dylib" "$APP/$EXE" >/dev/null
elif command -v optool >/dev/null 2>&1; then
  optool install -c load -p "@executable_path/FFMenu.dylib" -t "$APP/$EXE" >/dev/null
else
  echo "instala insert_dylib u optool"; exit 1
fi

if command -v ldid >/dev/null 2>&1; then
  ldid -S "$APP/$EXE"
  ldid -S "$APP/FFMenu.dylib"
fi

mkdir -p dist
OUT="dist/$(basename "${IPA%.ipa}")-mod.ipa"
rm -f "$OUT"
(cd "$W" && zip -qry "$OLDPWD/$OUT" Payload)
rm -rf "$W"
echo "listo: $OUT"
echo "firma con Sideloadly o Azule e instala"
EOF

chmod +x build.sh

cat > README.md <<'EOF'
# FF Menu

Dylib con panel nativo: holograma (ESP) y aim.

## Antes de compilar

1. IPA **descifrada** de Free Fire.
2. `Il2CppDumper UnityFramework global-metadata.dat salida/`
3. En `salida/dump.cs` busca la clase jugador y los nombres de hueso.
4. Rellena el bloque `CONFIGURA AQUÍ` de `Tweak.xm`.

## Compilar

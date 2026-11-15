#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <IOKit/hid/IOHIDEvent.h>
#import <IOKit/hidsystem/IOHIDEventSystemClient.h>
#import <dlfcn.h>
#import <math.h>

#pragma mark - il2cpp

typedef void   *(*f_dg)(void);
typedef void  **(*f_dga)(void *, size_t *);
typedef void   *(*f_ai)(void *);
typedef void   *(*f_cfn)(void *, const char *, const char *);
typedef void   *(*f_cgm)(void *, const char *, int);
typedef void   *(*f_ri)(void *, void *, void **, void **);
typedef void   *(*f_cgt)(void *);
typedef void   *(*f_tgo)(void *);

static f_dg  p_dg;  static f_dga p_dga; static f_ai p_ai;
static f_cfn p_cfn; static f_cgm p_cgm; static f_ri p_ri;
static f_cgt p_cgt; static f_tgo p_tgo;

static void *gKObj, *gKCam, *gKPlayer;

static BOOL resolve(void) {
    void *h = dlopen("@rpath/UnityFramework.framework/UnityFramework", RTLD_NOW);
    if (!h) h = dlopen("/usr/lib/libil2cpp.so", RTLD_NOW);
    if (!h) return NO;
    #define R(n) if (!(p_##n = (void *)dlsym(h, "il2cpp_" #n))) return NO;
    R(dg) R(dga) R(ai) R(cfn) R(cgm) R(ri)
    if (!(p_cgt = (void *)dlsym(h, "il2cpp_class_get_type"))) return NO;
    if (!(p_tgo = (void *)dlsym(h, "il2cpp_type_get_object"))) return NO;
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
    V3 z = {0,0,0};
    if (!transform) return z;
    void *m = p_cgm(gKObj, "get_position", 0);
    if (!m) return z;
    return unbox(p_ri(m, transform, NULL, NULL));
}

static void *find_child(void *transform, const char *name) {
    if (!transform) return NULL;
    void *m = p_cgm(klass("UnityEngine", "Transform"), "Find", 1);
    void *s = ((void *(*)(const char *))dlsym(RTLD_DEFAULT, "il2cpp_string_new"))(name);
    return p_ri(m, transform, (void *[]){s}, NULL);
}

static void *get_transform(void *comp) {
    void *m = p_cgm(klass("UnityEngine", "Component"), "get_transform", 0);
    return p_ri(m, comp, NULL, NULL);
}

// devuelve lista de jugadores
static int players(void ***out) {
    void *m = p_cgm(gKObj, "FindObjectsOfType", 1);
    if (!m || !gKPlayer) return 0;
    void *t = p_tgo(p_cgt(gKPlayer));
    void *arr = p_ri(m, NULL, (void *[]){t}, NULL);
    if (!arr) return 0;
    uint64_t len = *(uint64_t *)((char *)arr + 0x18);
    *out = (void **)((char *)arr + 0x20);
    return (int)len;
}

// mundo -> pantalla
static CGPoint w2s(void *cam, V3 w) {
    void *m = p_cgm(gKCam, "WorldToScreenPoint", 1);
    V3 v = w;
    void *r = p_ri(m, cam, (void *[]){&v}, NULL);
    if (!r) return CGPointMake(-1, -1);
    V3 s = unbox(r);
    if (s.z < 0) return CGPointMake(-1, -1);
    return CGPointMake(s.x, UIScreen.mainScreen.bounds.size.height - s.y);
}

#pragma mark - ajustes

static BOOL gHolo = YES, gAim = NO, gTap = NO;
static float gFov = 140, gSmooth = 42, gDelay = 0.08;
static NSString *gBone = @"Head";

#pragma mark - toque sintético

static IOHIDEventSystemClientRef gClient;
static void inject(CGPoint p) {
    if (!gClient) gClient = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault);
    IOHIDEventRef e = IOHIDEventCreateDigitizerEvent(
        kCFAllocatorDefault, mach_absolute_time(),
        kIOHIDDigitizerTransducerTypeFinger, 0, 0,
        kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch,
        0, p.x, p.y, 0, 1.0f, 0, true, true, kIOHIDEventOptionNone);
    IOHIDEventSystemClientDispatchEvent(gClient, e);
    CFRelease(e);
}

#pragma mark - overlay

@interface FFView : UIView @end
@implementation FFView

- (void)drawRect:(CGRect)r {
    CGContextRef c = UIGraphicsGetCurrentContext();
    void **list; int n = players(&list);
    if (n <= 0) return;

    void *cam = p_ri(p_cgm(gKCam, "get_main", 0), NULL, NULL, NULL);
    if (!cam) return;

    CGPoint ctr = CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r));

    for (int i = 0; i < n; i++) {
        void *p = list[i];
        if (!p) continue;
        void *tr = get_transform(p);
        void *head = find_child(tr, gBone.UTF8String);
        V3 hp = pos_of(head);
        CGPoint s = w2s(cam, hp);
        if (s.x < 0) continue;

        float dist = hypotf(s.x - ctr.x, s.y - ctr.y);

        if (gHolo) {
            CGContextSetStrokeColorWithColor(c, UIColor.orangeColor.CGColor);
            CGContextSetLineWidth(c, 1.5);
            CGContextStrokeRect(c, CGRectMake(s.x - 18, s.y - 34, 36, 68));
            CGContextStrokeEllipseInRect(c, CGRectMake(s.x - 6, s.y - 6, 12, 12));
        }

        if (gAim && dist < gFov) {
            float k = gSmooth / 100.0f;
            CGPoint to = CGPointMake(ctr.x + (s.x - ctr.x) * k,
                                     ctr.y + (s.y - ctr.y) * k);
            inject(to);
            if (gTap) {
                usleep((useconds_t)(gDelay * 1e6));
                inject(to);
            }
            break;
        }
    }
}
@end

static UIWindow *gWin;
static FFView *gView;
static CADisplayLink *gLink;

static void tick(void) { [gView setNeedsDisplay]; }

#pragma mark - panel

static UIWindow *gPanel;

static UILabel *lbl(NSString *t) {
    UILabel *l = [UILabel new];
    l.text = t; l.font = [UIFont boldSystemFontOfSize:12];
    l.textColor = UIColor.whiteColor;
    return l;
}

static UISwitch *sw(BOOL on, SEL a, id t) {
    UISwitch *s = [UISwitch new];
    s.on = on;
    [s addTarget:t action:a forControlEvents:UIControlEventValueChanged];
    return s;
}

@interface FFMenu : NSObject
@property UIWindow *panel;
@end

@implementation FFMenu

- (void)holo:(UISwitch *)s { gHolo = s.on; }
- (void)aim:(UISwitch *)s  { gAim = s.on; }
- (void)tap:(UISwitch *)s  { gTap = s.on; }
- (void)fov:(UISlider *)s  { gFov = s.value; }
- (void)smo:(UISlider *)s  { gSmooth = s.value; }

- (UIStackView *)row:(NSString *)t ctl:(UIView *)c {
    UIStackView *h = [[UIStackView alloc] initWithArrangedSubviews:@[lbl(t), c]];
    h.axis = UILayoutConstraintAxisHorizontal;
    h.distribution = UIStackViewDistributionEqualSpacing;
    h.alignment = UIStackViewAlignmentCenter;
    return h;
}

- (void)open {
    self.panel = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 260, 300)];
    self.panel.center = CGPointMake(UIScreen.mainScreen.bounds.size.width / 2,
                                    UIScreen.mainScreen.bounds.size.height / 2);
    self.panel.windowLevel = UIWindowLevelAlert + 2;
    self.panel.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.94];
    self.panel.layer.cornerRadius = 18;
    self.panel.layer.masksToBounds = YES;
    self.panel.hidden = NO;

    UIViewController *vc = [UIViewController new];
    self.panel.rootViewController = vc;

    UIStackView *st = [[UIStackView alloc] initWithFrame:CGRectInset(self.panel.bounds, 16, 16)];
    st.axis = UILayoutConstraintAxisVertical;
    st.spacing = 10;

    UILabel *t = lbl(@"FF MENU");
    t.font = [UIFont boldSystemFontOfSize:15];
    [st addArrangedSubview:t];
    [st addArrangedSubview:[self row:@"Holograma" ctl:sw(gHolo, @selector(holo:), self)]];
    [st addArrangedSubview:[self row:@"Aimbot"    ctl:sw(gAim,  @selector(aim:),  self)]];
    [st addArrangedSubview:[self row:@"One tap"   ctl:sw(gTap,  @selector(tap:),  self)]];

    UISlider *f = [UISlider new];
    f.minimumValue = 60; f.maximumValue = 320; f.value = gFov;
    [f addTarget:self action:@selector(fov:) forControlEvents:UIControlEventValueChanged];
    [st addArrangedSubview:[self row:@"FOV" ctl:f]];

    UISlider *s = [UISlider new];
    s.minimumValue = 1; s.maximumValue = 100; s.value = gSmooth;
    [s addTarget:self action:@selector(smo:) forControlEvents:UIControlEventValueChanged];
    [st addArrangedSubview:[self row:@"Suavizado" ctl:s]];

    [vc.view addSubview:st];
}

- (void)close {
    self.panel.hidden = YES;
    self.panel = nil;
}
@end

static FFMenu *gMenu;
static UIButton *gBtn;

static void setup(void) {
    gKObj    = klass("UnityEngine", "Object");
    gKCam    = klass("UnityEngine", "Camera");
    gKPlayer = klass("", "Player");
    if (!gKObj || !gKCam || !gKPlayer) return;

    gWin = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    gWin.windowLevel = UIWindowLevelAlert + 1;
    gWin.backgroundColor = UIColor.clearColor;
    gWin.userInteractionEnabled = NO;
    gWin.rootViewController = [UIViewController new];
    gView = [[FFView alloc] initWithFrame:gWin.bounds];
    gView.backgroundColor = UIColor.clearColor;
    gView.opaque = NO;
    [gWin.rootViewController.view addSubview:gView];
    gWin.hidden = NO;

    gLink = [CADisplayLink displayLinkWithTarget:gView selector:@selector(setNeedsDisplay)];
    [gLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];

    gMenu = [FFMenu new];

    gWin.userInteractionEnabled = YES;
    gBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    gBtn.frame = CGRectMake(14, 120, 52, 52);
    gBtn.layer.cornerRadius = 26;
    gBtn.backgroundColor = [UIColor colorWithRed:1 green:0.36 blue:0 alpha:0.85];
    [gBtn setTitle:@"FF" forState:UIControlStateNormal];
    [gBtn setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    [gBtn addTarget:gMenu action:@selector(open) forControlEvents:UIControlEventTouchUpInside];
    [gView addSubview:gBtn];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:gBtn
                                                                        action:@selector(pan:)];
    [gBtn addGestureRecognizer:pan];
    gView.userInteractionEnabled = YES;
}

static void (^panBlock)(UIPanGestureRecognizer *) = ^(UIPanGestureRecognizer *g) {
    CGPoint d = [g translationInView:g.view];
    g.view.center = CGPointMake(g.view.center.x + d.x, g.view.center.y + d.y);
    [g setTranslation:CGPointZero inView:g.view];
};

#pragma mark - arranque

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
    });
}

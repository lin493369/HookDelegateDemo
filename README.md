## iOS 如何优雅地 hook 系统的 delegate 方法？

在 iOS 开发中我们经常需要去 hook 系统方法，来满足一些特定的应用场景。

比如使用 Swizzling 来实现一些 AOP 的日志功能，比较常见的例子是 hook `UIViewController` 的 `viewDidLoad` ，动态为其插入日志。

这当然是一个很经典的例子，能让开发者迅速了解这个知识点。不过正如现在的娱乐圈，diss 天 diss 地，如果我们也想 hook 天，hook 地，顺便 hook 一下系统的 delegate 方法，该怎么做呢？

所以就进入今天的主题：**如何优雅地 hook 系统的 delegate 方法？**


#### hook 系统类的实例方法

首先，我们回想一下 hook `UIViewController` 的 `viewDidLoad` 方法，我们需要使用 category，为什么需要 category 呢？因为在 category 里面才能在不入侵源码的情况下，拿到实例方法 `viewDidLoad` ，并实现替换：

```
#import "UIViewController+swizzling.h"
#import <objc/runtime.h>
@implementation UIViewController (swizzling)

+ (void)load {

    // 通过 class_getInstanceMethod() 函数从当前对象中的 method list 获取 method 结构体，如果是类方法就使用 class_getClassMethod() 函数获取.
    Method fromMethod = class_getInstanceMethod([self class], @selector(viewDidLoad));
    Method toMethod = class_getInstanceMethod([self class], @selector(swizzlingViewDidLoad));
    // 这里直接交换方法，不做判断，因为 UIViewController 的 viewDidLoad 肯定实现了。
    method_exchangeImplementations(fromMethod, toMethod);
}
// 我们自己实现的方法，也就是和self的viewDidLoad方法进行交换的方法。
- (void)swizzlingViewDidLoad {
    NSString *str = [NSString stringWithFormat:@"%@", self.class];
    NSLog(@"日志打点 : %@", self.class);
    [self swizzlingViewDidLoad];
}
@end
```

这个例子里面，有一个注意点，通常我们创建 `ViewController` 都是继承于 `UIViewController`，因此如果想要使用这个日志打点功能，在自定义 `ViewController` 里面需要调用 `[super viewDidLoad]`。所以一定需要明白，这个例子是替换 `UIViewController` 的 `viewDidLoad`，而不是全部子类的 `viewDidLoad`。

```
@implementation ViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    //
}
@end
```

#### hook webView 的 delegate 方法

这个需求最初是项目中需要统计所有 `webView` 相关的数据，因此需要 hook webView 的 `delegate` 方法，今天也是以此为例，主要是 hook `UIWebView`（`WKWebView`类似）。

首先，我们需要明白，调用 delegate 的对象，是继承了 UIWebViewDelegate 协议的对象，因此如果要 hook delegate 方法，我们先要找到这个对象。

因此我们需要 hook `[UIWebView setDelegate:<id>delegate]` 方法，拿到 delegate 对象，才能动态地替换该方法。这里 swizzling 上场：

```
@implementation UIWebView(delegate)

+(void)load{
    // hook UIWebView
    Method originalMethod = class_getInstanceMethod([UIWebView class], @selector(setDelegate:));
    Method swizzledMethod = class_getInstanceMethod([UIWebView class], @selector(hook_setDelegate:));
    method_exchangeImplementations(originalMethod, swizzledMethod);
}

- (void)dz_setDelegate:(id<UIWebViewDelegate>)delegate{
    [self dz_setDelegate:delegate];

    // 拿到 delegate 对象，在这里做替换 delegate 方法的操作

}
@end
```

这里有个局限性，源码中需要调用 `setDelegate:` 方法，这样才会调用 `dz_setDelegate:`。

接下来就是重点了，我们需要根据两种情况去动态地 hook delegate 方法，以 hook `webViewDidFinishLoad:` 为例：

- delegate 对象实现了 `webViewDidFinishLoad:` 方法。则交换实现。
- delegate 对象未实现了 `webViewDidFinishLoad:` 方法。则动态添加该 delegate 方法。

下面是 category 实现的完整代码，实现了以上两种情况下都能正确统计页面加载完成的数据：

```
static void dz_exchangeMethod(Class originalClass, SEL originalSel, Class replacedClass, SEL replacedSel, SEL orginReplaceSel){
    // 原方法
    Method originalMethod = class_getInstanceMethod(originalClass, originalSel);
    // 替换方法
    Method replacedMethod = class_getInstanceMethod(replacedClass, replacedSel);
    // 如果没有实现 delegate 方法，则手动动态添加
    if (!originalMethod) {
        Method orginReplaceMethod = class_getInstanceMethod(replacedClass, orginReplaceSel);
        BOOL didAddOriginMethod = class_addMethod(originalClass, originalSel, method_getImplementation(orginReplaceMethod), method_getTypeEncoding(orginReplaceMethod));
        if (didAddOriginMethod) {
            NSLog(@"did Add Origin Replace Method");
        }
        return;
    }
    // 向实现 delegate 的类中添加新的方法
    // 这里是向 originalClass 的 replaceSel（@selector(replace_webViewDidFinishLoad:)） 添加 replaceMethod
    BOOL didAddMethod = class_addMethod(originalClass, replacedSel, method_getImplementation(replacedMethod), method_getTypeEncoding(replacedMethod));
    if (didAddMethod) {
        // 添加成功
        NSLog(@"class_addMethod_success --> (%@)", NSStringFromSelector(replacedSel));
        // 重新拿到添加被添加的 method,这里是关键(注意这里 originalClass, 不 replacedClass), 因为替换的方法已经添加到原类中了, 应该交换原类中的两个方法
        Method newMethod = class_getInstanceMethod(originalClass, replacedSel);
        // 实现交换
        method_exchangeImplementations(originalMethod, newMethod);
    }else{
        // 添加失败，则说明已经 hook 过该类的 delegate 方法，防止多次交换。
        NSLog(@"Already hook class --> (%@)",NSStringFromClass(originalClass));
    }
}

@implementation UIWebView(delegate)

+(void)load{
    // hook WebView
    Method originalMethod = class_getInstanceMethod([UIWebView class], @selector(setDelegate:));
    Method swizzledMethod = class_getInstanceMethod([UIWebView class], @selector(dz_setDelegate:));
    method_exchangeImplementations(originalMethod, swizzledMethod);
}

- (void)dz_setDelegate:(id<UIWebViewDelegate>)delegate{
    [self dz_setDelegate:delegate];
    // 获得 delegate 的实际调用类
    // 传递给 UIWebView 来交换方法
    [self exchangeUIWebViewDelegateMethod:delegate];
}

#pragma mark - hook webView delegate 方法

- (void)exchangeUIWebViewDelegateMethod:(id)delegate{
    dz_exchangeMethod([delegate class], @selector(webViewDidFinishLoad:), [self class], @selector(replace_webViewDidFinishLoad:),@selector(oriReplace_webViewDidFinishLoad:));
}

// 在未添加该 delegate 的情况下，手动添加 delegate 方法。
- (void)oriReplace_webViewDidFinishLoad:(UIWebView *)webView{
    NSLog(@"统计加载完成数据");
}

// 在添加该 delegate 的情况下，使用 swizzling 交换方法实现。
// 交换后的具体方法实现
- (void)replace_webViewDidFinishLoad:(UIWebView *)webView
{
    NSLog(@"统计加载完成数据");
    [self replace_webViewDidFinishLoad:webView];
}

@end
```

与 hook 实例方法不相同的地方是，交换的两个类以及方法都不是 [self class]，在实现过程中:

1. 判断 delegate 对象的 delegate 方法（`originalMethod`）是否为空，为空则用 `class_addMethod` 为 delegate 对象添加方法名为 (`webViewDidFinishLoad:`) ，方法实现为（`oriReplace_webViewDidFinishLoad:`）的动态方法。

2. 若已实现，则说明该 delegate 对象实现了 `webViewDidFinishLoad:` 方法，此时不能简单地交换 `originalMethod` 与 `replacedMethod`，因为 `replaceMethod` 是属于 `UIWebView` 的实例方法，没有实现 delegate 协议，无法在 hook 之后调用原来的 delegate 方法：`[self replace_webViewDidFinishLoad:webView];`。

    因此，我们也需要将 `replace_webViewDidFinishLoad:` 方法动态添加到 delegate 对象中，并使用添加后的方法和源方法交换。

以上，通过动态添加方法并替换的方式，可以在不入侵源码的情况下，优雅地 hook 系统的 delegate 方法。通过合理使用 runtime 期间几个方法的特性，使得 hook 系统未实现的 delegate 方法成为可能。

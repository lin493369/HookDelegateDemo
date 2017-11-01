//
//  ViewController.m
//  HookDelegateDemo
//
//  Created by admin on 2017/11/1.
//  Copyright © 2017年 getui. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()<UIWebViewDelegate>
@property (strong, nonatomic) IBOutlet UIWebView *webView;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    _webView.delegate = self;
    NSURLRequest *urlRequest = [[NSURLRequest alloc]initWithURL:[NSURL URLWithString:@"https://www.baidu.com"]];
    [_webView loadRequest:urlRequest];
}

-(void)webViewDidFinishLoad:(UIWebView *)webView{
    NSLog(@"original method handle");
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end

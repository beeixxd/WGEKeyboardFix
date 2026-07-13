- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    [self.view endEditing:YES];
    
    for (int i = 1; i <= 5; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.view endEditing:YES];
            [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder) to:nil from:nil forEvent:nil];
        });
    }
}

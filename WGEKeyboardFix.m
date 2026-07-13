- (void)handleUnlockSuccessAndDismissSafely {
    self.view.alpha = 0.0;
    
    [self.view endEditing:YES];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.presentingViewController) {
            [self dismissViewControllerAnimated:NO completion:nil];
        } else {
            [self.view removeFromSuperview];
            [self removeFromParentViewController];
        }
    });
}

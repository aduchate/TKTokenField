//
//  TKTokenTextView.m
//  CustomTokenField
//
//  Created by Antoine Duchateau on 14/06/15.
//  Copyright (c) 2015 Taktik SA. All rights reserved.
//

#import "TKTokenTextView.h"
#import "TKTokenFieldAttachmentCell.h"
#import "TKTokenFieldAttachment.h"
#import "TKTokenField.h"

@implementation TKTokenTextView

- (id) initWithFrame:(NSRect)frameRect {
    if (self = [super initWithFrame:frameRect]) {
        
    }
    return self;
}

- (TKTokenField*) tokenField {
    //Peek the responder chain
    NSResponder * r = [self nextResponder];
    while (r && ![r isKindOfClass:[TKTokenField class]]) {
        r = [r nextResponder];
    }
    return (TKTokenField*) r;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    // Drawing code here.
}

- (NSRange) rangeOfAttachment:(NSTextAttachment*) theAttachment indexOfToken:(NSInteger *) index {
    //Take latest set of typed characters and put them into at TKTokenFieldAttachment
    NSUInteger length = self.textStorage.length;
    NSRange effectiveRange = NSMakeRange(0, 0);
    NSInteger foundIndex = 0;
    
    id attachment;
    while (NSMaxRange(effectiveRange) < length) {
        attachment = [self.textStorage attribute:NSAttachmentAttributeName atIndex:NSMaxRange(effectiveRange) effectiveRange:&effectiveRange];
        if (attachment == theAttachment) {
            if (index) { *index = foundIndex; }
            return effectiveRange;
        }
        foundIndex++;
    }
    return NSMakeRange(NSNotFound, 0);
}

- (void) makeToken:(NSEvent *) theEvent {
    NSRange effectiveRange = [self rangeOfAttachment:nil indexOfToken:nil];
    if (effectiveRange.location == NSNotFound) { return; }
    
    NSAttributedString * tokenString = [self.textStorage attributedSubstringFromRange:effectiveRange];

    TKTokenFieldAttachment *token = [self.tokenField makeTokenFieldAttachment:[tokenString string] range:effectiveRange];
    NSAttributedString * replacementString = [NSAttributedString attributedStringWithAttachment:token];

    NSRect rect = [self firstRectForCharacterRange:effectiveRange actualRange:nil]; //screen coordinates
    rect = [self.window convertRectFromScreen:rect];
    rect.origin = [self convertPoint:rect.origin fromView:nil];

    [self.tokenField prepareInsertion:token range:effectiveRange rect:rect];
    if ([self shouldChangeTextInRange:effectiveRange replacementString:replacementString.string]) {
        [self.textStorage replaceCharactersInRange:effectiveRange withAttributedString:replacementString];
        [self didChangeText];
    }
    [self.tokenField finishInsertion:token range:effectiveRange rect:rect];
}

- (void) keyDown:(NSEvent *)theEvent {
    if (theEvent.characters.length && [self.tokenizingCharacterSet characterIsMember:[theEvent.characters characterAtIndex:0]]) {
        [self makeToken:theEvent];
    } else {
        [super keyDown:theEvent];
        
        NSRange initiallyTypedTextRange = [self rangeOfAttachment:nil indexOfToken:nil];
        if (self.selectedRange.length>0 && self.selectedRange.location>=initiallyTypedTextRange.location) {
            initiallyTypedTextRange.length = MIN(initiallyTypedTextRange.length, self.selectedRange.location - initiallyTypedTextRange.location);
        }
        if (initiallyTypedTextRange.length>2) {
            NSString * initiallyTypedText = [[self.textStorage attributedSubstringFromRange:initiallyTypedTextRange] string];
            
            NSLog(@"Previous: %@, Current: %@",self.previousCompletionString,initiallyTypedText);
            if (![self.previousCompletionString isEqualToString:initiallyTypedText]) {
                NSLog(@"complete it!");
                int64_t delayInSeconds = self.completionDelay;
                
                dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
                dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                    NSInteger indexOfToken = -1;
                    NSRange subsequentlyTypedTextRange = [self rangeOfAttachment:nil indexOfToken:&indexOfToken];
                    if (self.selectedRange.length>0 && self.selectedRange.location>=subsequentlyTypedTextRange.location) {
                        subsequentlyTypedTextRange.length = MIN(subsequentlyTypedTextRange.length, self.selectedRange.location - subsequentlyTypedTextRange.location);
                    }
                    if (subsequentlyTypedTextRange.length>2) {
                        NSString * subsequentlyTypedText = [[self.textStorage attributedSubstringFromRange:subsequentlyTypedTextRange] string];
                        
                        if ([subsequentlyTypedText isEqualToString:initiallyTypedText]) {
                            //Support asynchronous and synchronous versions
                            if ([self.tokenField.delegate respondsToSelector:@selector(tokenField:completionsForSubstring:indexOfToken:indexOfSelectedItem:)]) {
                                NSInteger preferredItem;
                                self.completions = [(id<TKTokenFieldDelegate>)self.tokenField.delegate tokenField:self.tokenField completionsForSubstring:subsequentlyTypedText indexOfToken:indexOfToken indexOfSelectedItem:&preferredItem];
                                self.indexOfCompletion = preferredItem;
                                self.completionRange = subsequentlyTypedTextRange;
                                self.previousCompletionString = subsequentlyTypedText;
                                [self complete:self];
                            } else if ([self.tokenField.delegate respondsToSelector:@selector(tokenField:completionsForSubstring:indexOfToken:completionHandler:)]) {
                                [(id<TKTokenFieldDelegate>)self.tokenField.delegate tokenField:self.tokenField completionsForSubstring:subsequentlyTypedText indexOfToken:indexOfToken completionHandler:^(NSArray *suggestions, NSInteger preferredItem, NSError *error) {

                                    NSInteger indexOfToken = -1;
                                    NSRange finallyTypedTextRange = [self rangeOfAttachment:nil indexOfToken:&indexOfToken];
                                    if (self.selectedRange.length>0 && self.selectedRange.location>=finallyTypedTextRange.location) {
                                        finallyTypedTextRange.length = MIN(finallyTypedTextRange.length, self.selectedRange.location - finallyTypedTextRange.location);
                                    }
                                    if (finallyTypedTextRange.length>2) {
                                        NSString * finallyTypedText = [[self.textStorage attributedSubstringFromRange:finallyTypedTextRange] string];
                                        
                                        if ([finallyTypedText isEqualToString:initiallyTypedText]) {
                                            self.completions = suggestions;
                                            self.indexOfCompletion = preferredItem;
                                            self.completionRange = finallyTypedTextRange;
                                            self.previousCompletionString = finallyTypedText;
                                            [self complete:self];
                                        }
                                    }
                                }];
                            }
                        }
                    }
                });
            }
        }
    }
}

- (void) didChangeText {
    [super didChangeText];
    
    [self.tokenField invalidateIntrinsicContentSize];
}

- (NSArray *)completionsForPartialWordRange:(NSRange)charRange
                        indexOfSelectedItem:(NSInteger *)index {
    if (index && self.indexOfCompletion>-1) { *index = self.indexOfCompletion; }
    return self.completions;
}

- (void) complete:(id)sender {
    [super complete:sender];
}

- (void)insertCompletion:(NSString *)word
     forPartialWordRange:(NSRange)charRange
                movement:(NSInteger)movement
                 isFinal:(BOOL)flag {
    [super insertCompletion:word forPartialWordRange:charRange movement:movement isFinal:flag];
}

- (NSRange) rangeForUserCompletion {
    return self.completionRange;
}

- (void)setSelectedRange:(NSRange)selectedRange
                affinity:(NSSelectionAffinity)affinity
          stillSelecting:(BOOL)flag {
    [super setSelectedRange:selectedRange affinity:affinity stillSelecting:flag];
    
    NSRect rect = [self firstRectForCharacterRange:selectedRange actualRange:nil]; //screen coordinates
    rect = [self.window convertRectFromScreen:rect];
    rect.origin = [self convertPoint:rect.origin fromView:nil];
    
    rect.origin.y += 6;
    rect.size.height = 12;
    [self.tokenField scrollRectToVisible:rect];
}
@end
//
//  CheatController.m
//  Pcsxr
//

#import <Cocoa/Cocoa.h>
#include "psxcommon.h"
#include "cheat.h"
#import "CheatController.h"
#import "ARCBridge.h"
#import "PcsxrCheatHandler.h"
#import "PcsxrHexadecimalFormatter.h"

#define kTempCheatCodesName @"tempCheatCodes"
#define kCheatsName @"cheats"
@implementation PcsxrCheatTempObject
@synthesize address, value;

- (NSNumber *)addressNS
{
	return @(self.address);
}
- (void)setAddressNS:(NSNumber *)addressNS
{
	self.address = [addressNS unsignedIntValue];
}

- (NSNumber *)valueNS
{
	return @(self.value);
}
- (void)setValueNS:(NSNumber *)valueNS
{
	self.value = [valueNS unsignedShortValue];
}

- (id)init
{
	return self = [self initWithAddress:0x10000000 value:0];
}

- (id)initWithAddress:(uint32_t)add value:(uint16_t)val
{
	if (self = [super init]) {
		self.address = add;
		self.value = val;
	}
	return self;
}

- (id)initWithCheatCode:(CheatCode *)theCheat
{
	return [self initWithAddress:theCheat->Addr value:theCheat->Val];
}

- (NSString*)description
{
	return [NSString stringWithFormat:@"%08x %04x", address, value];
}

- (BOOL)isEqual:(id)object
{
	if ([object isKindOfClass:[PcsxrCheatTempObject class]]) {
		if (address != [(PcsxrCheatTempObject*)object address]) {
			return NO;
		} else if (value != [(PcsxrCheatTempObject*)object value]) {
			return NO;
		} else
			return YES;
	} else
		return NO;
}

- (id)copyWithZone:(NSZone *)zone
{
	return [[[self class] alloc] initWithAddress:address value:value];
}

@end

@implementation PcsxrCheatTemp
@synthesize cheatName;
@synthesize cheatValues;
@synthesize enabled;

- (void)setCheatName:(NSString *)_cheatName
{
	if ([cheatName isEqualToString:_cheatName]) {
		return;
	}
	[self willChangeValueForKey:@"cheatName"];
#if __has_feature(objc_arc)
	cheatName = _cheatName;
#else
	NSString *temp = cheatName;
	cheatName = [_cheatName copy];
	[temp release];
#endif
	[self didChangeValueForKey:@"cheatName"];
}

- (id)initWithCheat:(Cheat *)theCheat
{
	if (self = [super init]) {
		self.cheatName = @(theCheat->Descr);
		self.enabled = theCheat->Enabled ? YES : NO;
		self.cheatValues = [NSMutableArray arrayWithCapacity:theCheat->n];
		for (int i = 0; i < theCheat->n; i++) {
			[cheatValues addObject:AUTORELEASEOBJ([[PcsxrCheatTempObject alloc] initWithCheatCode:&CheatCodes[i+theCheat->First]])];
		}
	}
	return self;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"[%@%@]\n%@", enabled ? @"*" : @"", cheatName, [cheatValues componentsJoinedByString:@"\n"]];
}

#if !__has_feature(objc_arc)
- (void)dealloc
{
	self.cheatName = nil;
	self.cheatValues = nil;
	
	[super dealloc];
}
#endif

@end

@implementation CheatController
@synthesize tempCheatCodes;
@synthesize cheats;

- (NSString *)windowNibName
{
	return @"CheatWindow";
}

- (id)init
{
	return self = [self initWithWindowNibName:@"CheatWindow"];
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
	if (self = [super initWithCoder:aDecoder]) {
		self.tempCheatCodes = [NSMutableArray array];
	}
	return self;
}

- (id)initWithWindow:(NSWindow *)window
{
	if (self = [super initWithWindow:window]) {
		self.tempCheatCodes = [NSMutableArray array];
	}
	return self;
}

- (void)refreshNSCheatArray
{
	NSMutableArray *tmpArray = [[NSMutableArray alloc] initWithCapacity:NumCheats];
	for (int i = 0; i < NumCheats; i++) {
		[tmpArray addObject:AUTORELEASEOBJ([[PcsxrCheatTemp alloc] initWithCheat:&Cheats[i]])];
	}
	self.cheats = tmpArray;
	RELEASEOBJ(tmpArray);
	[self setDocumentEdited:NO];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ([keyPath isEqualToString:kCheatsName]) {
		[self setDocumentEdited:YES];
	}
}

- (void)refresh
{
	[cheatView reloadData];
	[self refreshNSCheatArray];
}

- (void)awakeFromNib
{
	[valueFormatter setHexPadding:4];
	[addressFormatter setHexPadding:8];
	[self refreshNSCheatArray];
	[self addObserver:self forKeyPath:kCheatsName options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld context:NULL];
}

- (IBAction)loadCheats:(id)sender
{
	NSOpenPanel *openDlg = RETAINOBJ([NSOpenPanel openPanel]);
	[openDlg setCanChooseFiles:YES];
	[openDlg setCanChooseDirectories:NO];
	[openDlg setAllowsMultipleSelection:NO];
	[openDlg setAllowedFileTypes:[PcsxrCheatHandler supportedUTIs]];
	
	if ([openDlg runModal] == NSFileHandlingPanelOKButton) {
		NSURL *file = [openDlg URL];
		LoadCheats([[file path] fileSystemRepresentation]);
		[self refresh];
	}
	RELEASEOBJ(openDlg);
}

- (IBAction)saveCheats:(id)sender
{
	NSSavePanel *saveDlg = RETAINOBJ([NSSavePanel savePanel]);
	[saveDlg setAllowedFileTypes:[PcsxrCheatHandler supportedUTIs]];
	[saveDlg setCanSelectHiddenExtension:YES];
	[saveDlg setCanCreateDirectories:YES];
	[saveDlg setPrompt:NSLocalizedString(@"Save Cheats", nil)];
	if ([saveDlg runModal] == NSFileHandlingPanelOKButton) {
		NSURL *url = [saveDlg URL];
		NSString *saveString = [cheats componentsJoinedByString:@"\n"];
		[saveString writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	}
	RELEASEOBJ(saveDlg);
}

- (IBAction)clear:(id)sender
{
	self.cheats = [NSMutableArray array];
}

- (IBAction)closeCheatEdit:(id)sender
{
	[NSApp endSheet:editCheatWindow returnCode:[sender tag] == 1 ? NSCancelButton : NSOKButton];
}

- (IBAction)changeCheat:(id)sender
{
	[self setDocumentEdited:YES];
}

- (IBAction)removeCheatValue:(id)sender
{
	if ([editCheatView selectedRow] < 0) {
		NSBeep();
		return;
	}

	NSIndexSet *toRemoveIndex = [editCheatView selectedRowIndexes];
	[self willChange:NSKeyValueChangeRemoval valuesAtIndexes:toRemoveIndex forKey:kTempCheatCodesName];
	[tempCheatCodes removeObjectsAtIndexes:toRemoveIndex];
	[self didChange:NSKeyValueChangeRemoval valuesAtIndexes:toRemoveIndex forKey:kTempCheatCodesName];	
}

- (IBAction)addCheatValue:(id)sender
{
	[self willChange:NSKeyValueChangeInsertion valuesAtIndexes:[NSIndexSet indexSetWithIndex:[tempCheatCodes count]] forKey:kTempCheatCodesName];
	[tempCheatCodes addObject:AUTORELEASEOBJ([[PcsxrCheatTempObject alloc] init])];
	[self didChange:NSKeyValueChangeInsertion valuesAtIndexes:[NSIndexSet indexSetWithIndex:[tempCheatCodes count] - 1] forKey:kTempCheatCodesName];
}

- (void)reloadCheats
{
	NSFileManager *manager = [NSFileManager defaultManager];
	NSURL *tmpURL = [[manager URLForDirectory:NSItemReplacementDirectory inDomain:NSUserDomainMask appropriateForURL:[[NSBundle mainBundle] bundleURL] create:YES error:nil] URLByAppendingPathComponent:@"temp.cht" isDirectory:NO];
	NSString *tmpStr = [cheats componentsJoinedByString:@"\n"];
	[tmpStr writeToURL:tmpURL atomically:NO encoding:NSUTF8StringEncoding error:NULL];
	LoadCheats([[tmpURL path] fileSystemRepresentation]);
	[manager removeItemAtURL:tmpURL error:NULL];
}

- (void)editCheatCodeSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
	if (returnCode == NSOKButton) {
		PcsxrCheatTemp *tmpCheat = [cheats objectAtIndex:[cheatView selectedRow]];
		if (![tmpCheat.cheatValues isEqualToArray:tempCheatCodes]) {
			tmpCheat.cheatValues = tempCheatCodes;
			[self setDocumentEdited:YES];
		}
	}
	
	[sheet orderOut:nil];
}

- (IBAction)editCheat:(id)sender
{
	if ([cheatView selectedRow] < 0) {
		NSBeep();
		return;
	}
	NSMutableArray *tmpArray = [[cheats objectAtIndex:[cheatView selectedRow]] cheatValues];
	NSMutableArray *newCheats = [[NSMutableArray alloc] initWithArray:tmpArray copyItems:YES];
	self.tempCheatCodes = newCheats;
	RELEASEOBJ(newCheats);
	[NSApp beginSheet:editCheatWindow modalForWindow:[self window] modalDelegate:self didEndSelector:@selector(editCheatCodeSheetDidEnd:returnCode:contextInfo:) contextInfo:NULL];
}

- (IBAction)addCheat:(id)sender
{
	[self willChange:NSKeyValueChangeInsertion valuesAtIndexes:[NSIndexSet indexSetWithIndex:[cheats count]] forKey:kCheatsName];
	PcsxrCheatTemp *tmpCheat = [[PcsxrCheatTemp alloc] init];
	tmpCheat.cheatName = NSLocalizedString(@"New Cheat", @"New Cheat Name" );
	PcsxrCheatTempObject *tmpObj = [[PcsxrCheatTempObject alloc] initWithAddress:0x10000000 value:0];
	NSMutableArray *tmpArray = [NSMutableArray arrayWithObject:tmpObj];
	RELEASEOBJ(tmpObj);
	tmpCheat.cheatValues = tmpArray;
	[cheats addObject:tmpCheat];
	RELEASEOBJ(tmpCheat);
	[self didChange:NSKeyValueChangeInsertion valuesAtIndexes:[NSIndexSet indexSetWithIndex:[cheats count] - 1] forKey:kCheatsName];
	[self setDocumentEdited:YES];
}

- (IBAction)applyCheats:(id)sender
{
	[self reloadCheats];
	[self setDocumentEdited:NO];
}

- (void)sheetDidDismiss:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void  *)contextInfo
{
	switch (returnCode) {
		case NSAlertDefaultReturn:
			[self reloadCheats];
			[self close];
			break;
			
		default:
			[self refreshNSCheatArray];
			[self close];
			break;
			
		case NSAlertOtherReturn:
			break;
	}
}

- (BOOL)windowShouldClose:(id)sender
{
	if (![sender isDocumentEdited] || ![[self window] isEqual:sender]) {
		return YES;
	} else {
		NSBeginAlertSheet(NSLocalizedString(@"Unsaved Changes", @"Unsaved changes"),
						  NSLocalizedString(@"Save", @"Save"),
						  NSLocalizedString(@"Don't Save",@"Don't Save"),
						  NSLocalizedString(@"Cancel", @"Cancel"), [self window], self,
						  NULL, @selector(sheetDidDismiss:returnCode:contextInfo:), NULL,
						  NSLocalizedString(@"The cheat codes have not been applied. Unapplied cheats will not run nor be saved. Do you wish to save?",nil));
		
		return NO;
	}
}

- (IBAction)removeCheats:(id)sender
{
	if ([cheatView selectedRow] < 0) {
		NSBeep();
		return;
	}
	
	NSIndexSet *toRemoveIndex = [cheatView selectedRowIndexes];
	[self willChange:NSKeyValueChangeRemoval valuesAtIndexes:toRemoveIndex forKey:kCheatsName];
	[cheats removeObjectsAtIndexes:toRemoveIndex];
	[self didChange:NSKeyValueChangeRemoval valuesAtIndexes:toRemoveIndex forKey:kCheatsName];
	[self setDocumentEdited:YES];
}

@end
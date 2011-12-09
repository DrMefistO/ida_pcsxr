//
//  PcsxrMemCardManager.m
//  Pcsxr
//
//  Created by Charles Betts on 11/23/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "PcsxrMemCardController.h"
#import "PcsxrMemoryObject.h"
#import "ConfigurationController.h"
#include "sio.h"

#define MAX_MEMCARD_BLOCKS 15

//FIXME: This code uses similar code to the GTK memory card manager, and both don't recognize saves that span multiple blocks.

static inline void CopyMemcardData(char *from, char *to, int *i, char *str, int copy) {
	memcpy(to + (*i + 1) * 128, from + (copy + 1) * 128, 128);
	SaveMcd(str, to, (*i + 1) * 128, 128);
	memcpy(to + (*i + 1) * 1024 * 8, from + (copy + 1) * 1024 * 8, 1024 * 8);
	SaveMcd(str, to, (*i + 1) * 1024 * 8, 1024 * 8);
}

@implementation PcsxrMemCardController

//memCard1Array KVO functions

-(void)insertObject:(PcsxrMemoryObject *)p inMemCard1ArrayAtIndex:(NSUInteger)index {
    [memCard1Array insertObject:p atIndex:index];
}

-(void)removeObjectFromMemCard1ArrayAtIndex:(NSUInteger)index {
    [memCard1Array removeObjectAtIndex:index];
}

- (void)setMemCard1Array:(NSMutableArray *)a
{
	if (memCard1Array != a) {
		[memCard1Array release];
		memCard1Array = [[NSMutableArray alloc] initWithArray:a];
	}
}

- (NSArray *)memCard1Array
{
	return memCard1Array;
}

//memCard2Array KVO functions

-(void)insertObject:(PcsxrMemoryObject *)p inMemCard2ArrayAtIndex:(NSUInteger)index {
    [memCard2Array insertObject:p atIndex:index];
}

-(void)removeObjectFromMemCard2ArrayAtIndex:(NSUInteger)index {
    [memCard2Array removeObjectAtIndex:index];
}

- (void)setMemCard2Array:(NSMutableArray *)a
{
	if (memCard2Array != a) {
		[memCard2Array release];
		memCard2Array = [[NSMutableArray alloc] initWithArray:a];
	}
}

- (NSArray *)memCard2Array
{
	return memCard2Array;
}


- (id)init
{
	self = [self initWithWindowNibName:@"MemCardManager"];
	return self;
}

- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if (self) {
        LoadMcds(Config.Mcd1, Config.Mcd2);
    }
    
    return self;
}

- (void)loadMemoryCardInfoForCard:(int)theCard
{
	NSInteger i;
	McdBlock info;
	NSMutableArray *newArray = [[NSMutableArray alloc] initWithCapacity:MAX_MEMCARD_BLOCKS];
	
	for (i = 0; i < MAX_MEMCARD_BLOCKS; i++) {
		GetMcdBlockInfo(theCard, i + 1, &info);
		PcsxrMemoryObject *ob = [[PcsxrMemoryObject alloc] initWithMcdBlock:&info];

		[newArray insertObject:ob atIndex:i];
		[ob release];
	}
	if (theCard == 1) {
		[self setMemCard1Array:newArray];
	} else {
		[self setMemCard2Array:newArray];
	}
	[newArray release];
}

- (void)memoryCardDidChangeNotification:(NSNotification *)aNote
{
	LoadMcd(1, Config.Mcd1);
	[self loadMemoryCardInfoForCard:1];
	LoadMcd(2, Config.Mcd2);
	[self loadMemoryCardInfoForCard:2];
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
	[[self window] setDelegate:self];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(memoryCardDidChangeNotification:) name:memChangeNotifier object:nil];

}

- (void)windowDidBecomeKey:(NSNotification *)notification
{
	LoadMcd(1, Config.Mcd1);
	[self loadMemoryCardInfoForCard:1];
	LoadMcd(2, Config.Mcd2);
	[self loadMemoryCardInfoForCard:2];
}

- (int)findFreeMemCardBlockInCard:(int)target_card
{
#if 0
	BOOL found = NO;
	NSString *blockName;
	NSArray *cardArray;
	if (target_card == 1) {
		cardArray = [self memCard1Array];
	}else {
		cardArray = [self memCard2Array];
	}
	
	int i = 0;
	while (i < MAX_MEMCARD_BLOCKS && found == NO) {
		blockName = [[cardArray objectAtIndex:i] englishName];
		//FIXME: Does this properly handle saves that span more than one block?
		if ([blockName isEqualToString:@""]) {
			found = YES;
		} else {
			i++;
		}
	}
	if (found == YES)
		return i;
	
	// no free slots, try to find a deleted one
	i = 0;
	while (i < MAX_MEMCARD_BLOCKS && found == NO) {
		unsigned char flags = [[cardArray objectAtIndex:i] memFlags];
		if ((flags & 0xF0) != 0x50) {
			found = YES;
		} else {
			i++;
		}
	}
	if (found == YES)
		return i;
#else
	int i;
	for (i = 0; i < MAX_MEMCARD_BLOCKS; i++) {
		if ([self isMemoryBlockEmptyOnCard:target_card block:i]) {
			return i;
		}
	}
#endif
	
	return -1;
}

- (IBAction)moveBlock:(id)sender
{
	NSInteger memCardSelect = [sender tag];
	NSCollectionView *cardView;
	NSIndexSet *selection;
	int toCard, freeSlot;
	char *str, *source, *destination;
	if (memCardSelect == 1) {
		str = Config.Mcd1;
		source = Mcd2Data;
		destination = Mcd1Data;
		cardView = memCard2view;
		toCard = 1;
	} else {
		str = Config.Mcd2;
		source = Mcd1Data;
		destination = Mcd2Data;
		cardView = memCard1view;
		toCard = 2;
	}
	selection = [cardView selectionIndexes];
	if (!selection || [selection count] == 0) {
		NSBeep();
		return;
	}
	
	NSInteger selectedIndex = [selection firstIndex];
	
	freeSlot = [self findFreeMemCardBlockInCard:toCard];
	if (freeSlot == -1) {
		NSRunCriticalAlertPanel(NSLocalizedString(@"No Free Space", nil), [NSString stringWithFormat:NSLocalizedString(@"Memory card %d doesn't have a free block on it. Please remove some blocks on that card to continue", nil), toCard], NSLocalizedString(@"Okay", nil), nil, nil);
		return;
	}
	
	CopyMemcardData(source, destination, &freeSlot, str, selectedIndex);
	
	if (toCard == 1) {
		LoadMcd(1, Config.Mcd1);
	} else {
		LoadMcd(2, Config.Mcd2);
	}
	[self loadMemoryCardInfoForCard:toCard];
}

- (IBAction)formatCard:(id)sender
{
	NSInteger formatOkay = NSRunAlertPanel(NSLocalizedString(@"Format Card", nil), NSLocalizedString(@"Formatting a memory card will remove all data on it.\n\nThis cannot be undone.", nil), NSLocalizedString(@"Cancel", nil), NSLocalizedString(@"Format", nil), nil);
	if (formatOkay == NSAlertAlternateReturn) {
		NSInteger memCardSelect = [sender tag];
		if (memCardSelect == 1) {
			CreateMcd(Config.Mcd1);
			LoadMcd(1, Config.Mcd1);
		} else {
			CreateMcd(Config.Mcd2);
			LoadMcd(2, Config.Mcd2);
		}
		[self loadMemoryCardInfoForCard:memCardSelect];
	}
}

- (void)deleteMemoryBlockAtSlot:(int)slotnum card:(int)cardNum
{
	int xor = 0, i, j;
	char *data, *ptr, *filename;
	NSArray *cardArray;
	PcsxrMemoryObject *memObject;
	if (cardNum == 1) {
		filename = Config.Mcd1;
		data = Mcd1Data;
		cardArray = [self memCard1Array];
	} else {
		filename = Config.Mcd2;
		data = Mcd2Data;
		cardArray = [self memCard2Array];
	}
	memObject = [cardArray objectAtIndex:slotnum];
	unsigned char flags = [memObject memFlags];
	i = slotnum;
	i++;
	ptr = data + i * 128;
	
	if ((flags & 0xF0) == 0xA0) {
		if ((flags & 0xF) >= 1 &&
			(flags & 0xF) <= 3) { // deleted
			*ptr = 0x50 | (flags & 0xF);
		} else return;
	} else if ((flags & 0xF0) == 0x50) { // used
		*ptr = 0xA0 | (flags & 0xF);
	} else { return; }
	
	for (j = 0; j < 127; j++) xor ^= *ptr++;
	*ptr = xor;
	
	SaveMcd(filename, data, i * 128, 128);

}

- (IBAction)deleteMemoryObject:(id)sender {
	NSInteger deleteOkay = NSRunAlertPanel(NSLocalizedString(@"Delete Block", nil), NSLocalizedString(@"Deleting a block will remove all saved data on that block.\n\nThis cannot be undone.", nil), NSLocalizedString(@"Cancel", nil), NSLocalizedString(@"Delete", nil), nil);
	if (deleteOkay == NSAlertAlternateReturn) {
		NSInteger memCardSelect = [sender tag];
		NSIndexSet *selected;
		if (memCardSelect == 1) {
			selected = [memCard1view selectionIndexes];
		} else {
			selected = [memCard2view selectionIndexes];
		}
		
		if (!selected || [selected count] == 0) {
			NSBeep();
			return;
		}
		
		NSInteger selectedIndex = [selected firstIndex];
		[self deleteMemoryBlockAtSlot:selectedIndex card:memCardSelect];
		
		if (memCardSelect == 1) {
			LoadMcd(1, Config.Mcd1);
		} else {
			LoadMcd(2, Config.Mcd2);
		}
		[self loadMemoryCardInfoForCard:memCardSelect];
	}
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	[super dealloc];
}

- (BOOL)isMemoryBlockEmptyOnCard:(int)aCard block:(int)aBlock
{
	NSArray *memArray;
	PcsxrMemoryObject *obj;
	if (aCard == 1) {
		memArray = [self memCard1Array];
	} else {
		memArray = [self memCard2Array];
	}
	obj = [memArray objectAtIndex:aBlock];
#if 0
	if (([obj memFlags] & 0xF0) != 0x50)
		return YES;
	
	//FIXME: Does this properly handle saves that span more than one block?
	if ([[obj englishName] isEqualToString:@""]) {
		return YES;
	}
#else
	if (![obj isNotDeleted]) {
		return YES;
	} 
#endif
	
	return NO;
}

- (int)countFreeBlocksOnCard:(int)aCard
{
	int i, count = 0;
	for (i = 0; i < MAX_MEMCARD_BLOCKS; i++) {
		if ([self isMemoryBlockEmptyOnCard:aCard block:i]) {
			count++;
		}
	}
	return count;
}

@end

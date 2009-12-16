#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <sqlite3.h>
#import <UIKit/UIKit.h>
#import <UIKit/UIApplication.h>
#import <SpringBoard/SBApplicationController.h>
#import <SpringBoard/SBApplication.h>
#include "Plugin.h"

extern "C" CFStringRef UIDateFormatStringForFormatType(CFStringRef type);

#define localize(bundle, str) \
	[bundle localizedStringForKey:str value:str table:nil]

static SBApplication* getApp()
{
	Class cls = objc_getClass("SBApplicationController");
	SBApplicationController* ctr = [cls sharedInstance];

	SBApplication* app = [ctr applicationWithDisplayIdentifier:@"com.culturedcode.ThingsTouch"];
	
	return app;
}

@interface DotView : UIView

@property (nonatomic, retain) UIColor* color;

@end

@implementation DotView

@synthesize color;

-(void) drawRect:(CGRect) rect
{
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	[self.color set];
	CGContextFillEllipseInRect(ctx, rect);

	NSBundle* b = [NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/CalendarUI.framework"];
	NSString* path = [b pathForResource:@"dotshine" ofType:@"png"];
	UIImage* image = [UIImage imageWithContentsOfFile:path];
	[image drawInRect:rect];
}
@end

@interface ThingsView : UIView

@property (nonatomic, retain) DotView* dot;
@property (nonatomic, retain) LILabel* name;
@property (nonatomic, retain) LILabel* due;
@property (nonatomic, retain) UIImageView* priority;

@end

@implementation ThingsView

@synthesize dot, due, name, priority;

@end

static ThingsView* createView(CGRect frame, LITableView* table)
{
	ThingsView* v = [[[ThingsView alloc] initWithFrame:frame] autorelease];
	v.backgroundColor = [UIColor clearColor];

	v.dot = [[[DotView alloc] initWithFrame:CGRectMake(4, 4, 9, 9)] autorelease];
	v.dot.backgroundColor = [UIColor clearColor];
	
	v.name = [table labelWithFrame:CGRectZero];
	v.name.frame = CGRectMake(22, 0, 275, 16);
	v.name.backgroundColor = [UIColor clearColor];

	v.due = [table labelWithFrame:CGRectZero];
	v.due.frame = CGRectMake(22, 16, 275, 14);
	v.due.backgroundColor = [UIColor clearColor];

	v.priority = [[[UIImageView alloc] initWithFrame:CGRectMake(305, 3, 10, 10)] autorelease];
	v.priority.backgroundColor = [UIColor clearColor];

	[v addSubview:v.dot];
	[v addSubview:v.due];
	[v addSubview:v.name];
	[v addSubview:v.priority];

	return v;
}


@interface ThingsPlugin : NSObject <LIPluginController, LITableViewDelegate, UITableViewDataSource> 
{
	NSTimeInterval lastUpdate;
}

@property (nonatomic, retain) LIPlugin* plugin;
@property (retain) NSDictionary* todoPrefs;
@property (retain) NSArray* todoList;

@property (retain) NSString* sql;
@property (retain) NSString* prefsPath;
@property (retain) NSString* dbPath;

@end

@implementation ThingsPlugin

@synthesize todoList, todoPrefs, sql, plugin, prefsPath, dbPath;

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section 
{
	return self.todoList.count;
}

- (UITableViewCell *)tableView:(LITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath 
{
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TodoCell"];
	
	if (cell == nil) {
		cell = [[[UITableViewCell alloc] initWithFrame:CGRectZero reuseIdentifier:@"TodoCell"] autorelease];
		//cell.backgroundColor = [UIColor clearColor];
		
		ThingsView* v = createView(CGRectMake(0, 0, 320, 35), tableView);
		v.tag = 57;
		[cell.contentView addSubview:v];
	}
	
	ThingsView* v = [cell.contentView viewWithTag:57];
	v.name.style = tableView.theme.summaryStyle;
	v.due.style = tableView.theme.detailStyle;
	
	NSDictionary* elem = [self.todoList objectAtIndex:indexPath.row];
	v.name.text = [elem objectForKey:@"name"];

	BOOL ind = true;
	if (NSNumber* b = [self.todoPrefs objectForKey:@"ShowListColors"])
		ind = b.boolValue;

//	if (ind)
//	{
//		UIColor* color = [UIColor colorWithRed:[[elem objectForKey:@"color_r"] doubleValue]
//					green:[[elem objectForKey:@"color_g"] doubleValue]
//					blue:[[elem objectForKey:@"color_b"] doubleValue]
//					alpha:1];
//		v.dot.color = color;
//		v.dot.hidden = false;
//		[v.dot setNeedsDisplay];
//	}
//	else
//	{
		v.dot.hidden = true;
//	}
		
	NSNumber* dateNum = [elem objectForKey:@"due"];
	if (dateNum.doubleValue == nil)
	{
		NSBundle* bundle = [NSBundle bundleForClass:[self class]];
		v.due.text = localize(bundle, @"No Due Date");
	}
	else
	{
		NSDate* date = [[[NSDate alloc] initWithTimeIntervalSinceReferenceDate:dateNum.doubleValue] autorelease];
		
		int secondsDifference = (int) [date timeIntervalSinceNow];
		int days = secondsDifference/86400;
				
		NSDateFormatter* df = [[[NSDateFormatter alloc] init] autorelease];
		df.dateFormat = (NSString*)UIDateFormatStringForFormatType(CFSTR("UIWeekdayNoYearDateFormat"));
		
		if (days < 0){
			NSString *overdueDays = [NSString stringWithFormat:@" (%d days overdue)", (days*(-1))];
			v.due.text = [[df stringFromDate:date] stringByAppendingString: overdueDays];
			
			UIColor* color = [UIColor colorWithRed:255
						green:0
						blue:0
						alpha:1];
			v.dot.color = color;
			v.dot.hidden = false;
			[v.dot setNeedsDisplay];			
		}
		else
			v.due.text = [df stringFromDate:date];
	}
	
	return cell;
}

- (id) initWithPlugin:(LIPlugin*) plugin
{
	self = [super init];
	self.plugin = plugin;
	
	plugin.tableViewDataSource = self;
	plugin.tableViewDelegate = self;

	NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(update:) name:LITimerNotification object:nil];
	[center addObserver:self selector:@selector(update:) name:LIViewReadyNotification object:nil];

	return self;
}

- (void) updateTasks
{
	if (self.dbPath == nil)
	{
		SBApplication* app = getApp();
		NSString* appPath = [app.path stringByDeletingLastPathComponent];
		self.dbPath = [[appPath stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:(@"db.sqlite3")];
		self.prefsPath = [appPath stringByAppendingFormat:@"/Library/Preferences/%@.plist", app.displayIdentifier];
	}

	self.todoPrefs = [NSDictionary dictionaryWithContentsOfFile:self.prefsPath];
	NSLog(@"LI:Things: Prefs: %@: %@", self.prefsPath, self.todoPrefs);
	
	//Appigo:	
	//NSString *allSql = @"select tasks.name, tasks.due_date, tasks.priority, lists.color from tasks left outer join lists on lists.pk = tasks.list where tasks.completion_date < 0 and tasks.deleted = 0";
	
	//Today tasks
	NSString *allSql = @"select title,dueDate from Task as t1 where status = 1 and type = 2 and flagged = 1 and dueDate IS NOT NULL";
		
	//BOOL hideUnfiled = false;
	//if (NSNumber* n = [self.plugin.preferences valueForKey:@"HideUnfiled"])
	//		hideUnfiled = n.boolValue;

	//if (hideUnfiled)
	//	allSql = [allSql stringByAppendingString:@" and tasks.list <> 0"];
	
	//BOOL dayLimit = true;
	//int maxDays = 7;
	//if (NSNumber* n = [self.plugin.preferences valueForKey:@"dayLimit"])
	//	dayLimit = n.boolValue;
	//if (NSNumber* n = [self.plugin.preferences valueForKey:@"maxDays"])
	//	maxDays = n.intValue;
	//if (dayLimit)
	//	allSql = [NSString stringWithFormat:@"%@ and (tasks.due_date < date('now', '+%i day') or tasks.due_date = 64092211200)", allSql, maxDays];
		
	//BOOL hideSubItems = true;
	//if (NSNumber* n = [self.plugin.preferences valueForKey:@"hideSubItems"])
	//	hideSubItems = n.boolValue;
	//if (hideSubItems)
	//	allSql = [allSql stringByAppendingString:@" and tasks.parent = 0"];
		
	//BOOL hideNoDate = false;
	//if (NSNumber* n = [self.plugin.preferences valueForKey:@"HideNoDate"])
	//	hideNoDate = n.boolValue;

	//if (hideNoDate)
	//	allSql = [allSql stringByAppendingString:@" and tasks.due_date <> 64092211200"];

	int queryLimit = 5;
	if (NSNumber* n = [self.plugin.preferences valueForKey:@"MaxTasks"])
		queryLimit = n.intValue;

	NSString* sql = [NSString stringWithFormat:@"%@ order by dueDate ASC limit %i", allSql, queryLimit];
	NSLog(@"LI:Things: Executing SQL: %@", sql);
			
	/* Get the todo database timestamp */
	NSFileManager* fm = [NSFileManager defaultManager];
	NSDictionary *dataFileAttributes = [[NSFileManager defaultManager] fileAttributesAtPath:self.dbPath traverseLink:YES];
	NSDate* lastDataModified = [dataFileAttributes objectForKey:NSFileModificationDate];
	
	if(![sql isEqualToString:self.sql] || lastUpdate < lastDataModified.timeIntervalSinceReferenceDate)
	{
		NSLog(@"LI:Things: Loading Todo Tasks...");
		self.sql = sql;

		// Update data and read from database
		NSMutableArray *todos = [NSMutableArray arrayWithCapacity:4];
		
		sqlite3 *database = NULL;
		@try
		{		
			if (sqlite3_open([self.dbPath UTF8String], &database) != SQLITE_OK) 
			{
				NSLog(@"LI:Things: Failed to open database.");
				return;
			}

			// Setup the SQL Statement and compile it for faster access
			sqlite3_stmt *compiledStatement = NULL;

			@try
			{
				if (sqlite3_prepare_v2(database, [sql UTF8String], -1, &compiledStatement, NULL) != SQLITE_OK) 
				{
					NSLog(@"LI:Things: Failed to prepare statement: %s", sqlite3_errmsg(database));
					return;
				}
								
				// Loop through the results and add them to the feeds array
				while(sqlite3_step(compiledStatement) == SQLITE_ROW) 
				{
					const char *cText = (const char*)sqlite3_column_text(compiledStatement, 0);
					double cDue  = sqlite3_column_double(compiledStatement, 1);
					int priority  = sqlite3_column_int(compiledStatement, 2);
					const char* cColor  = (const char*)sqlite3_column_text(compiledStatement, 3);
							
					NSString *aText = [NSString stringWithUTF8String:(cText == NULL ? "" : cText)];
					NSString *color = (cColor == NULL ? [self.todoPrefs objectForKey:@"UnfiledTaskListColor"] : [NSString stringWithUTF8String:cColor]);
					NSArray* colorComps = [color componentsSeparatedByString:@":"];
							
					NSDictionary *todoDict = [NSDictionary dictionaryWithObjectsAndKeys:
						aText, @"name",
						[NSNumber numberWithDouble:cDue], @"due",
						[NSNumber numberWithInt:priority], @"priority", 
						[NSNumber numberWithDouble:(colorComps.count == 4 ? [[colorComps objectAtIndex:0] doubleValue] : 0)], @"color_r",
						[NSNumber numberWithDouble:(colorComps.count == 4 ? [[colorComps objectAtIndex:1] doubleValue] : 0)], @"color_g",
						[NSNumber numberWithDouble:(colorComps.count == 4 ? [[colorComps objectAtIndex:2] doubleValue] : 0)], @"color_b",
						nil];
				
					[todos addObject:todoDict];
				}
			}
			@finally
			{			
				if (compiledStatement != NULL)
					sqlite3_finalize(compiledStatement);
			}
		}
		@finally
		{
			if (database != NULL)
				sqlite3_close(database);
		}
	
		[self performSelectorOnMainThread:@selector(setTodoList:) withObject:todos waitUntilDone:YES];	

		// Inside on SMS and outside on Weather Info.  This is likely location of SB crash
		NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithCapacity:1];
		[dict setObject:todos forKey:@"todos"];  
		[[NSNotificationCenter defaultCenter] postNotificationName:LIUpdateViewNotification object:self.plugin userInfo:dict];
		
		lastUpdate = lastDataModified.timeIntervalSinceReferenceDate;
	}
}

- (void) update:(NSNotification*) notif
{
	if (!self.plugin.enabled)
		return;

	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	[self updateTasks];
	[pool release];
}

@end

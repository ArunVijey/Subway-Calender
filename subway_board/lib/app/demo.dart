// A believable day of events, tasks and spending for the preview build
// (--dart-define=DEMO=true), so every screen has something on it. Only used
// when there's no saved data yet; ✕ in the top bar clears it all.
import '../core/model.dart';
import '../core/money.dart';
import '../core/tasks.dart';
import '../core/util.dart';

const kDemo = bool.fromEnvironment('DEMO');

bool isDemoId(String id) => id.startsWith('demo');

void seedDemo(AppData s) {
  final now = nowMs(), t0 = sod(now);
  int at(int dayOff, int h, [int m = 0]) => addDays(t0, dayOff) + (h * 60 + m) * kMin;
  String day(int off) => dstr(addDays(t0, off));
  final nowMin = DateTime.fromMillisecondsSinceEpoch(now).hour * 60 + DateTime.fromMillisecondsSinceEpoch(now).minute;
  int rel(int mins) => now - (now % (5 * kMin)) + mins * kMin;

  s.settings.welcomed = true;
  s.events.addAll([
    Event(id: 'demo-e1', title: 'AS5011 · Compressible Flow', loc: 'Aero Dept, Room 102', cat: 'A', start: rel(-25), end: rel(35), sample: true),
    Event(id: 'demo-e2', title: 'Thesis: shock-capturing draft', cat: 'B', start: rel(70), end: rel(160), sample: true),
    Event(id: 'demo-e3', title: 'Gym', loc: 'Powerpac Gym', cat: 'E', start: rel(240), end: rel(300), sample: true),
    Event(id: 'demo-e4', title: 'Dinner with Sam', loc: 'Third Wave Coffee', cat: 'F', start: rel(400), end: rel(480), sample: true),
    Event(id: 'demo-e5', title: 'Structures lab', loc: 'Hangar 2', cat: 'A', start: at(1, 10), end: at(1, 12), sample: true),
    Event(id: 'demo-e6', title: 'Propulsion quiz', cat: 'C', start: at(2, 9), end: at(2, 10), sample: true),
  ]);
  s.tasks.addAll([
    Task(id: 'demo-t1', title: 'Submit structures HW 4', cat: 'C', due: day(-1), time: 17 * 60),
    Task(id: 'demo-t2', title: 'Pay electricity bill', cat: 'D', due: day(0), time: ((nowMin + 300) ~/ 30 * 30).clamp(0, 1410), amount: 124000, mcat: 'bills'),
    Task(id: 'demo-t3', title: 'Email Prof. Rao about the CFD run', cat: 'A', due: day(0), star: true),
    Task(id: 'demo-t4', title: 'Groceries', cat: 'D', due: day(1), subs: [
      SubTask(id: 'demo-s1', title: 'Milk'),
      SubTask(id: 'demo-s2', title: 'Eggs', done: true),
      SubTask(id: 'demo-s3', title: 'Coffee beans'),
    ]),
    Task(id: 'demo-t5', title: 'Pay rent', cat: 'D', due: dstr(addMonths(monthStart(now), 1)), repeat: 'monthly', amount: 1500000, mcat: 'bills'),
    Task(id: 'demo-t6', title: 'Read Anderson ch. 4 (oblique shocks)', cat: 'B', notes: 'θ–β–M relation, then the problems at the end.'),
    Task(id: 'demo-t7', title: 'Renew metro card', cat: 'D', due: day(3), amount: 50000, mcat: 'travel'),
    Task(id: 'demo-t8', title: 'Book train tickets home', cat: 'D', done: true, doneAt: now - 3 * kHour),
  ]);
  seedDemoMoney(s);
}

/// The money half of the demo. Also run on its own for a preview that was
/// seeded before accounts, goals and trip budgets existed (old demo spends are
/// replaced; anything else stays).
void seedDemoMoney(AppData s) {
  final now = nowMs(), t0 = sod(now);
  final m = s.money..budget = 3000000;
  m.txns.removeWhere((t) => isDemoId(t.id));
  final month0 = monthStart(now);
  int past(int daysAgo, int h) => math0(month0, addDays(t0, -daysAgo) + h * kHour);
  // Earlier months: real dates, for the charts.
  int ago(int daysAgo, int h) => addDays(t0, -daysAgo) + h * kHour;

  m.accounts.addAll([
    Account(id: 'demo-a1', name: 'SBI Savings', type: 'checking', color: '#1d6cf2', opening: 4200000),
    Account(id: 'demo-a2', name: 'HDFC Credit', type: 'credit', color: '#f87171'),
    Account(id: 'demo-a3', name: 'Cash', type: 'cash', color: '#22c55e', opening: 300000),
  ]);
  m.defaultAcct = 'demo-a2';
  m.goals.addAll([
    Goal(id: 'demo-g1', name: 'Laptop', emoji: '💻', color: '#8b5cf6', target: 9000000, end: addMonths(month0, 6), start: ago(80, 10)),
    Goal(id: 'demo-g2', name: 'Emergency fund', emoji: '🛟', color: '#14b8a6', target: 15000000, offset: 6000000, start: ago(200, 10)),
    Goal(id: 'demo-l1', name: 'Sam', emoji: '🤝', color: '#ff8a00', kind: 'lent', start: ago(12, 10)),
    Goal(id: 'demo-l2', name: 'Bike loan', emoji: '🛵', color: '#1d6cf2', kind: 'borrowed', longTerm: true, target: 12000000, end: addMonths(month0, 30), start: ago(150, 10)),
  ]);
  m.plans.add(Plan(id: 'demo-p1', name: 'Goa trip', emoji: '🏖️', color: '#ff5a1f', amount: 2500000, start: addDays(t0, -3), end: addDays(t0, 4), cats: const [], mode: 'added'));

  Txn x(String id, String title, String cat, int at, int amount, {String type = 'spend', String acct = 'demo-a2', String to = '', String goal = '', String plan = '', bool review = false}) =>
      Txn(id: 'demo-$id', title: title, cat: cat, at: at, amount: amount, type: type, acct: acct, to: to, goal: goal, plan: plan, review: review);

  m.txns.addAll([
    x('x1', 'Lunch', 'food', past(0, 13), 18000),
    x('x2', 'Metro', 'travel', past(0, 9), 4000, acct: 'demo-a3'),
    x('x3', 'Groceries', 'food', past(1, 19), 124000),
    x('x4', 'Coffee', 'food', past(1, 16), 22000, acct: 'demo-a3'),
    x('x5', 'Netflix', 'fun', past(3, 21), 64900),
    x('x6', 'Amazon · headphones', 'shop', past(5, 12), 189900),
    x('x7', 'Pharmacy', 'health', past(6, 18), 34000),
    x('x8', 'Swiggy', 'food', past(7, 21), 41200),
    x('x9', 'Uber', 'travel', past(8, 23), 26700),
    x('xa', 'Stipend', 'inc-salary', past(15, 10), 3700000, type: 'income', acct: 'demo-a1'),
    x('xb', 'Amazon refund', 'shop', past(2, 11), 45000, type: 'refund'),
    x('xc', 'Card bill', 'bills', past(4, 20), 260000, type: 'transfer', acct: 'demo-a1', to: 'demo-a2'),
    x('xd', 'Beach shack dinner', 'food', past(1, 21), 230000, plan: 'demo-p1'),
    x('xe', 'Scooter rental', 'travel', past(2, 10), 120000, plan: 'demo-p1'),
    x('xf', 'Paytm · unknown', 'other', past(0, 8), 9900, review: true),
    x('xg', 'Zomato', 'food', past(1, 22), 38900, review: true),
    x('xh', 'To laptop fund', 'other', past(10, 9), 1500000, type: 'save', acct: 'demo-a1', goal: 'demo-g1'),
    x('xi', 'Lent to Sam', 'other', ago(12, 18), 500000, type: 'lent', acct: 'demo-a1', goal: 'demo-l1'),
    x('xj', 'Sam paid back', 'other', past(3, 19), 200000, type: 'repay', acct: 'demo-a1', goal: 'demo-l1'),
    x('xk', 'Bike loan', 'other', ago(150, 10), 12000000, type: 'borrowed', acct: 'demo-a1', goal: 'demo-l2'),
    x('xl', 'Bike EMI', 'other', ago(120, 10), 450000, type: 'repay', acct: 'demo-a1', goal: 'demo-l2'),
    x('xm', 'Bike EMI', 'other', ago(90, 10), 450000, type: 'repay', acct: 'demo-a1', goal: 'demo-l2'),
    x('xn', 'Bike EMI', 'other', ago(60, 10), 450000, type: 'repay', acct: 'demo-a1', goal: 'demo-l2'),
    x('xo', 'Bike EMI', 'other', ago(30, 10), 450000, type: 'repay', acct: 'demo-a1', goal: 'demo-l2'),
    x('xp', 'To laptop fund', 'other', ago(45, 9), 1500000, type: 'save', acct: 'demo-a1', goal: 'demo-g1'),
  ]);
  // Five earlier months of everyday spending and pay, so the reports have history.
  const plan = [('Rent', 'bills', 1500000, 2), ('Groceries', 'food', 310000, 6), ('Swiggy', 'food', 180000, 12), ('Metro card', 'travel', 90000, 9), ('Uber', 'travel', 140000, 17), ('Myntra', 'shop', 260000, 20), ('Movie night', 'fun', 90000, 23), ('Pharmacy', 'health', 60000, 26)];
  for (var mo = 1; mo <= 5; mo++) {
    final base = addMonths(month0, -mo);
    for (final (title, cat, amt, day) in plan) {
      final at = DateTime.fromMillisecondsSinceEpoch(base).add(Duration(days: day - 1, hours: 13)).millisecondsSinceEpoch;
      m.txns.add(x('h$mo$day', title, cat, at, (amt * (0.75 + 0.1 * ((mo * 7 + day) % 5))).round()));
    }
    m.txns.add(x('i$mo', 'Stipend', 'inc-salary', DateTime.fromMillisecondsSinceEpoch(base).add(const Duration(days: 14, hours: 10)).millisecondsSinceEpoch, 3700000, type: 'income', acct: 'demo-a1'));
  }
  m.cats.firstWhere((c) => c.id == 'food').budget = 800000;
  m.cats.firstWhere((c) => c.id == 'travel').budget = 200000;
  m.cats.firstWhere((c) => c.id == 'fun').budget = 150000;
  m.cats.firstWhere((c) => c.id == 'shop').budget = 250000;
}
/// Keeps a back-dated demo spend inside this month.
int math0(int month0, int at) => at < month0 ? month0 + 10 * kHour : at;

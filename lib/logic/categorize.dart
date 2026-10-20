import '../core/fmt.dart';
import '../data/categories.dart';
import '../data/models.dart';
import 'text_keys.dart';

/// Categoria suggerita per una descrizione: prima le regole imparate (la più
/// lunga che combacia), poi le parole note. [amount] serve a non mettere una
/// spesa in una categoria di entrate e viceversa.
String? suggestCategory(String desc, Iterable<Rule> rules, {int amount = -1, Map<String, Category>? cats}) {
  final text = fold(desc);
  if (text.trim().isEmpty) return null;
  bool fits(String catId) {
    final c = cats?[catId];
    if (c == null) return true;
    if (c.isTransfer) return true;
    return amount < 0 ? c.isExpense : c.isIncome;
  }

  Rule? best;
  for (final r in rules) {
    if (r.pattern.length < 2 || !containsWord(text, r.pattern) || !fits(r.catId)) continue;
    if (best == null || r.pattern.length > best.pattern.length) best = r;
  }
  if (best != null) return best.catId;
  String? bestB;
  var bestLen = 0;
  for (final e in builtinRules.entries) {
    if (e.key.length > bestLen && containsWord(text, e.key) && fits(e.value)) {
      bestB = e.value;
      bestLen = e.key.length;
    }
  }
  return bestB;
}

/// Regola da imparare quando l'utente sceglie [catId] per [desc]: null se la
/// descrizione non ha parole utili o la regola esiste già uguale.
Rule? learnRule(String desc, String catId, Iterable<Rule> rules, String Function() newId) {
  final key = merchantKey(desc);
  if (key.length < 3) return null;
  for (final r in rules) {
    if (r.pattern == key) {
      if (r.catId == catId) return null;
      return Rule(id: r.id, pattern: key, catId: catId, rename: r.rename, hits: r.hits);
    }
  }
  return Rule(id: newId(), pattern: key, catId: catId);
}

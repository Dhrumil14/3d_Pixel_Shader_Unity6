using System.Collections.Generic;

namespace FuzzyGraph.Runtime
{
    public class WorldStateQuery
    {
        private readonly Dictionary<string, FuzzyValue> values = new();

        public void Set(string key, FuzzyValue value)
        {
            values[key] = value;
        }

        public bool TryGet(string key, out FuzzyValue value)
        {
            return values.TryGetValue(key, out value);
        }

        public bool Contains(string key)
        {
            return values.ContainsKey(key);
        }

        public IReadOnlyDictionary<string, FuzzyValue> Values => values;
    }
}
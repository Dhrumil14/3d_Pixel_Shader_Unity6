using System;
using System.Collections.Generic;

namespace FuzzyGraph.Runtime
{
    [Serializable]
    public class RuntimeRule
    {
        public string ruleID;
        public string eventID;
        public int priority;

        public List<RuntimeCriteria> Criteria = new();
        public List<RuntimeConsequence> Consequences = new();
    }
}
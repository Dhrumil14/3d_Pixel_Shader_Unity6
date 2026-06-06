using System;

namespace FuzzyGraph.Runtime
{
    public enum ConsequenceType
    {
        Dialogue,
        SetFlag,
        AddScore,
        FireEvent,
        WriteBack
    }

    [Serializable]
    public class RuntimeConsequence
    {
        public ConsequenceType consequenceType;
        public string targetKey;
        public FuzzyValue val;
        public string payLoad;
    }
}
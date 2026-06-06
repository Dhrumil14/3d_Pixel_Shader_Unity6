using UnityEngine;
using System;

namespace FuzzyGraph.Runtime
{
    public enum FuzzyValueType
    {
        Bool,
        Int,
        Float,
        String
    }

    [Serializable]
    public struct FuzzyValue
    {
        public FuzzyValueType type;
        public bool boolVal;
        public float floatVal;
        public string stringVal;
        public int intVal;

        public static FuzzyValue FromBool(bool val)
        {
            return new FuzzyValue
            {
                type = FuzzyValueType.Bool,
                boolVal = val
            };
        }

        public static FuzzyValue FromInt(int val)
        {
            return new FuzzyValue
            {
                type = FuzzyValueType.Int,
                intVal = val
            };
        }

        public static FuzzyValue FromFloat(float val)
        {
            return new FuzzyValue
            {
                type = FuzzyValueType.Float,
                floatVal = val
            };
        }

        public static FuzzyValue FromString(string val)
        {
            return new FuzzyValue
            {
                type = FuzzyValueType.String,
                stringVal = val
            };
        }

        public override string ToString()
        {
            return type switch
            {
                FuzzyValueType.Bool => boolVal.ToString(),
                FuzzyValueType.Int => intVal.ToString(),
                FuzzyValueType.Float => floatVal.ToString(),
                FuzzyValueType.String => stringVal,
                _ => "Unknown"
            };
        }
    }
}



using System;

namespace FuzzyGraph.Runtime
{
    [Serializable]
    public class RuntimeCriteria
    {
        public string fieldKey;
        public CriteriaOperator criteriaOperator;
        public FuzzyValue expectedVal;

        public bool Matches(WorldStateQuery query)
        {
            bool exists = query.TryGet(fieldKey, out FuzzyValue actualVal);
            if(criteriaOperator == CriteriaOperator.Exists)
            {
                return exists;
            }

            if(criteriaOperator == CriteriaOperator.DoesNotExist)
            {
                return !exists;
            }

            if(!exists)
            {
                return false;
            }

            if(actualVal.type != expectedVal.type)
            {
                return false;
            }

            return actualVal.type switch
            {
                FuzzyValueType.Bool => CompareBool(actualVal.boolVal, expectedVal.boolVal),
                FuzzyValueType.Int => CompareInt(actualVal.intVal, expectedVal.intVal),
                FuzzyValueType.Float => CompareFloat(actualVal.floatVal, expectedVal.floatVal),
                FuzzyValueType.String => CompareString(actualVal.stringVal, expectedVal.stringVal),
                _ => false
            };
        }

        private bool CompareBool(bool actual, bool expected)
        {
            return criteriaOperator switch
            {
                CriteriaOperator.Equals => actual == expected,
                CriteriaOperator.NotEquals => actual != expected,
                _ => false
            };
        }

        private bool CompareInt(int actual, int expected)
        {
            return criteriaOperator switch
            {
                CriteriaOperator.Equals => actual == expected,
                CriteriaOperator.NotEquals => actual != expected,
                CriteriaOperator.GreaterThan => actual > expected,
                CriteriaOperator.GreaterThanOrEqual => actual >= expected,
                CriteriaOperator.LessThan => actual < expected,
                CriteriaOperator.LessThanOrEqual => actual <= expected,
                _ => false
            };
        }

        private bool CompareFloat(float actual, float expected)
        {
            return criteriaOperator switch
            {
                CriteriaOperator.Equals => Math.Abs(actual - expected) < 0.0001f,
                CriteriaOperator.NotEquals => Math.Abs(actual - expected) >= 0.0001f,
                CriteriaOperator.GreaterThan => actual > expected,
                CriteriaOperator.GreaterThanOrEqual => actual >= expected,
                CriteriaOperator.LessThan => actual < expected,
                CriteriaOperator.LessThanOrEqual => actual <= expected,
                _ => false
            };
        }

        private bool CompareString(string actual, string expected)
        {
            return criteriaOperator switch
            {
                CriteriaOperator.Equals => actual == expected,
                CriteriaOperator.NotEquals => actual != expected,
                _ => false
            };
        }
    }
}
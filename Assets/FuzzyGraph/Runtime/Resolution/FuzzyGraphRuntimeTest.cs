using UnityEngine;
using System.Collections.Generic;

namespace FuzzyGraph.Runtime
{
    public class FuzzyGraphRuntimeTest : MonoBehaviour
    {
        private void Start()
        {
            WorldStateQuery query = new WorldStateQuery();

            query.Set("Player.HasStolenItem", FuzzyValue.FromBool(true));
            query.Set("Guard.Relationship", FuzzyValue.FromInt(2));
            query.Set("Player.LiedBefore", FuzzyValue.FromBool(true));

            List<RuntimeRule> rules = new()
            {
                new RuntimeRule
                {
                    ruleID = "generic_guard_response",
                    eventID = "talkToGuard",
                    priority = 0,
                    Criteria = new List<RuntimeCriteria>
                    {
                        new RuntimeCriteria
                        {
                            fieldKey = "Player.HasStolenItem",
                            criteriaOperator = CriteriaOperator.Exists,
                            weight = 1f
                        }
                    },

                    Consequences = new List<RuntimeConsequence>
                    {
                        new RuntimeConsequence
                        {
                            consequenceType = ConsequenceType.Dialogue,
                            payLoad = "The Guard looks at you carefully."
                        }
                    }
                },

                new RuntimeRule
                {
                    ruleID = "suspicious_guard_response",
                    eventID = "talkToGuard",
                    priority = 10,
                    Criteria = new List<RuntimeCriteria>
                    {
                        new RuntimeCriteria
                        {
                            fieldKey = "Player.HasStolenItem",
                            criteriaOperator = CriteriaOperator.Equals,
                            expectedVal = FuzzyValue.FromBool(true),
                            weight = 5f
                        },
                        new RuntimeCriteria
                        {
                            fieldKey = "Guard.Relationship",
                            criteriaOperator = CriteriaOperator.LessThanOrEqual,
                            expectedVal = FuzzyValue.FromInt(3),
                            weight = 3f
                        },
                        new RuntimeCriteria
                        {
                            fieldKey = "Player.LiedBefore",
                            criteriaOperator = CriteriaOperator.Equals,
                            expectedVal = FuzzyValue.FromBool(true),
                            weight = 4f
                        }
                    },

                    Consequences = new List<RuntimeConsequence>
                    {
                        new RuntimeConsequence
                        {
                            consequenceType = ConsequenceType.Dialogue,
                            payLoad = "I know what you did there, Do NOT lie to me again."
                        }
                    }
                }
            };

            MatchResult result = RuleEvaluator.Evaluate(rules, query, "talkToGuard");

            if(!result.hasMatch)
            {
                Debug.Log("No matching rule found");
                return;
            }

            Debug.Log($"Winning Rule: {result.rule.ruleID}");
            Debug.Log($"Score: {result.scoreFloat:0.##}");

            foreach(RuntimeConsequence consequence in result.rule.Consequences)
            {
                Debug.Log($"Consequence: {consequence.consequenceType} | {consequence.payLoad}");
            }
        }
    }
}

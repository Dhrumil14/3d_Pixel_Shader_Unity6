using System;
using System.Collections.Generic;

namespace FuzzyGraph.Runtime
{
    public static class RuleEvaluator
    {
        public static MatchResult Evaluate(
            IEnumerable<RuntimeRule> rules,
            WorldStateQuery query,
            string eventId)
        {
            RuntimeRule bestRule = null;
            int bestScore = -1;
            int bestPriority = int.MinValue;

            foreach (RuntimeRule rule in rules)
            {
                if (!string.IsNullOrEmpty(rule.eventID) && rule.eventID != eventId)
                    continue;

                int score = CountMatchingCriteria(rule, query);

                if (score <= 0)
                    continue;

                bool isBetter = score > bestScore || score == bestScore && rule.priority > bestPriority;

                if (isBetter)
                {
                    bestRule = rule;
                    bestScore = score;
                    bestPriority = rule.priority;
                }
            }

            return new MatchResult
            {
                rule = bestRule,
                score = bestScore
            };
        }

        private static int CountMatchingCriteria(RuntimeRule rule, WorldStateQuery query)
        {
            int score = 0;
            foreach (RuntimeCriteria criteria in rule.Criteria)
            {
                if(criteria.Matches(query))
                    score++;
            }
            return score;
        }
    }
}
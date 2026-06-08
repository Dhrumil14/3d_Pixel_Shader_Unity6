namespace FuzzyGraph.Runtime
{
    public class MatchResult
    {
        public RuntimeRule rule;
        public int score;
        public bool hasMatch => rule != null;
    }
}